-- ProcFlare
-- Copyright (c) 2026 Bencepo. All rights reserved.
--
-- Lightweight proc alerts:
--   * Clearcasting: big pulsing icon above your character, sound and a short
--     screen-edge flash, shown as long as the buff lasts
--   * other procs (weapon enchants such as Crusader, trinkets, talents): a small
--     icon with countdown under it, and a softer sound
--   * debuff procs from you on your target (Icy Chill, Spell Vulnerability)
-- A "proc" is any new buff on you that lasts a short time (30 s by default),
-- comes from you and was not cast by you just before. No list to maintain:
-- new weapons and trinkets are picked up on their own.
-- Procs you do not care about are muted in the move mode with a right-click.

local ADDON = ...
local issecret = issecretvalue or function() return false end

local DEFAULTS = {
	clearcasting = true, -- Clearcasting alert
	procs = true,        -- alerts for other procs
	onlyMine = true,     -- only buffs that come from you (weapon, trinket, talent)
	targetProcs = true,  -- debuff procs from you on your target (Icy Chill, Spell Vulnerability)
	maxDuration = 30,    -- longest buff that still counts as a proc, in seconds
	ccSound = -1,        -- sound for Clearcasting (0 = none, below 0 = ProcFlare's own sound file)
	procSound = -2,      -- sound for other procs
	volume = 100,        -- volume of ProcFlare's own sounds in percent (25, 50, 75, 100)
	channel = "SFX",     -- sound channel: WoW's volume slider for it applies too
	flash = true,        -- screen-edge flash on Clearcasting
	scale = 100,         -- size in percent
	showMinimap = true,  -- minimap button
	reactive = true,     -- abilities that open up after a dodge, parry or block (Overpower, Riposte ...)
}

local _, CLASS = UnitClass("player")

-- The big alert: Clearcasting and its kin, procs that make the next spell free or instant.
-- Omen of Clarity (druid), Arcane Concentration (mage), Elemental Focus (shaman) and
-- Shadow Trance from Nightfall (warlock: the next Shadow Bolt is instant).
local BIG = {
	DRUID = { id = 16870, label = "Clearcasting" },
	MAGE = { id = 12536, label = "Clearcasting" },
	SHAMAN = { id = 16246, label = "Clearcasting" },
	WARLOCK = { id = 17941, label = "Shadow Trance", color = { 0.75, 0.4, 1 } },
}
local BIG_PROC = BIG[CLASS] or BIG.DRUID
local BIG_COLOR = BIG_PROC.color or { 0.45, 0.75, 1 }
local CC_IDS = { 16870, 12536, 16246, 17941 }
local CC_SET = {}
for _, id in ipairs(CC_IDS) do CC_SET[id] = true end

-- Abilities that only open up for a few seconds after a dodge, parry or block. The
-- first id names the spell; any rank known counts. Only the player's class is used.
local REACTIVE = {
	WARRIOR = { { 7384, 7887, 11584, 11585 }, { 6572, 6574, 7379, 11600, 11601, 25288 } }, -- Overpower, Revenge
	ROGUE = { { 14251 } }, -- Riposte
	HUNTER = { { 1495, 14269, 14270, 14271 }, { 19306, 20909, 20910 } }, -- Mongoose Bite, Counterattack
}
local REACTIVE_WINDOW = 5 -- seconds the game keeps them open

-- Known proc buffs of each class. Short buffs are found on their own, but Forever hides
-- buff details in combat; these are then asked for by spell id, so they still show.
local WATCH = {
	ALL = { 20007 }, -- Holy Strength (Crusader enchant)
	WARRIOR = { 12966, 12967, 12968, 12969, 12970, 12880, 14201, 14202, 14203, 14204 }, -- Flurry, Enrage
	SHAMAN = { 16257, 16277, 16278, 16279, 16280 }, -- Flurry
	PALADIN = { 20050, 20052, 20053, 20054, 20055, 20128, 20131, 20132, 20133, 20134 }, -- Vengeance, Redoubt
	ROGUE = { 14143, 14149 }, -- Remorseless Attacks
	HUNTER = { 6150 }, -- Quick Shots
	PRIEST = { 15271, 27828 }, -- Spirit Tap, Focused Casting (Martyrdom)
	DRUID = { 16886 }, -- Nature's Grace
}
local watchList = {}
for _, key in ipairs({ "ALL", CLASS }) do
	for _, id in ipairs(WATCH[key] or {}) do watchList[#watchList + 1] = id end
end

-- ProcFlare's own sounds, in four volume steps each (Sounds/<name>_<volume>.ogg).
local SOUND_FILES = {
	[-1] = "chime", [-2] = "ping",
	[-11] = "war_drums", [-12] = "war_horn", [-13] = "axe_clash", [-14] = "beast_roar", [-15] = "rage_spike", [-16] = "thud",
	[-21] = "arcane_surge", [-22] = "mana_burst", [-23] = "frost_shatter", [-24] = "fire_burst", [-25] = "power_chord", [-26] = "spark",
}

local SOUNDS = {
	{ 0, "None" },
	{ -11, "Melee: War drums" },
	{ -12, "Melee: War horn" },
	{ -13, "Melee: Axe clash" },
	{ -14, "Melee: Beast roar" },
	{ -15, "Melee: Rage spike" },
	{ -16, "Melee: Thud" },
	{ -21, "Caster: Arcane surge" },
	{ -22, "Caster: Mana burst" },
	{ -23, "Caster: Frost shatter" },
	{ -24, "Caster: Fire burst" },
	{ -25, "Caster: Power chord" },
	{ -26, "Caster: Spark" },
	{ -1, "ProcFlare chime" },
	{ -2, "ProcFlare ping" },
	{ 8959, "Game: Raid warning" },
	{ 8960, "Game: Ready check" },
	{ 12889, "Game: Alarm clock" },
	{ 3175, "Game: Map ping" },
	{ 18019, "Game: Toast" },
}

-- Sound packs: Clearcasting sound and proc sound.
local PACKS = {
	[1] = { name = "Melee", cc = -11, proc = -13 },
	[2] = { name = "Caster", cc = -21, proc = -26 },
}
local CHANNELS = { { "Master", "Master" }, { "SFX", "Sound effects" }, { "Ambience", "Ambience" }, { "Dialog", "Dialog" } }

local MAX_PROCS = 6
local PREVIEW_PROC = 20007 -- Holy Strength (Crusader enchant)

local db

local function spellName(id) return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) end
local function spellIcon(id) return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) end
local function playSound(id)
	if not id or id == 0 then return end
	local channel = (db and db.channel) or "SFX"
	if SOUND_FILES[id] then
		local v = (db and tonumber(db.volume)) or 100
		v = math.max(25, math.min(100, math.floor((v + 12) / 25) * 25))
		PlaySoundFile("Interface\\AddOns\\ProcFlare\\Sounds\\" .. SOUND_FILES[id] .. "_" .. v .. ".ogg", channel)
	elseif id > 0 then
		PlaySound(id, channel)
	end
end

-- Melee or caster, from class and, for hybrids, the talent tree with the most points.
local MELEE_CLASS = { WARRIOR = true, ROGUE = true, HUNTER = true, PALADIN = true, DEATHKNIGHT = true }
local MELEE_TREE = { DRUID = 2, SHAMAN = 2 } -- Feral Combat, Enhancement
local function guessPack()
	local _, class = UnitClass("player")
	if MELEE_CLASS[class] then return 1 end
	local tree = MELEE_TREE[class]
	if tree and GetTalentTabInfo then
		local best, bestPoints = nil, 0
		for i = 1, 3 do
			local r = { pcall(GetTalentTabInfo, i) }
			local points = r[1] and ((type(r[4]) == "number" and r[4]) or (type(r[6]) == "number" and r[6])) or 0
			if not issecret(points) and points > bestPoints then best, bestPoints = i, points end
		end
		if best == tree then return 1 end
	end
	return 2
end

local CC_NAME = spellName(BIG_PROC.id) or BIG_PROC.label

---------------------------------------------------------------- frames
local anchor = CreateFrame("Frame", "ProcFlareAnchor", UIParent)
anchor:SetSize(64, 64)
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local point, _, rel, x, y = self:GetPoint()
	db.point = { point, rel, x, y }
end)

local moveBg = anchor:CreateTexture(nil, "BACKGROUND")
moveBg:SetPoint("TOPLEFT", -6, 6)
moveBg:SetPoint("BOTTOMRIGHT", 6, -60)
moveBg:SetColorTexture(0.1, 0.4, 0.8, 0.35)
moveBg:Hide()
local moveText = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
moveText:SetPoint("BOTTOM", anchor, "TOP", 0, 10)
moveText:SetText("ProcFlare: drag to move, right-click a proc to mute it")
moveText:Hide()

-- Clearcasting: big icon with a pulsing glow.
local cc = CreateFrame("Frame", nil, anchor)
cc:SetAllPoints()
cc:Hide()
cc.icon = cc:CreateTexture(nil, "ARTWORK")
cc.icon:SetAllPoints()
cc.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
cc.icon:SetTexture(spellIcon(BIG_PROC.id))
cc.glow = cc:CreateTexture(nil, "OVERLAY")
cc.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
cc.glow:SetBlendMode("ADD")
cc.glow:SetVertexColor(BIG_COLOR[1], BIG_COLOR[2], BIG_COLOR[3])
cc.glow:SetPoint("CENTER")
cc.glow:SetSize(124, 124)
cc.label = cc:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
cc.label:SetPoint("TOP", cc, "BOTTOM", 0, -4)
cc.label:SetTextColor(math.min(BIG_COLOR[1] + 0.1, 1), math.min(BIG_COLOR[2] + 0.05, 1), 1)
cc.label:SetText(CC_NAME)
cc.time = cc:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
cc.time:SetPoint("BOTTOMRIGHT", -2, 2)
cc.count = cc:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
cc.count:SetPoint("TOPRIGHT", -2, -2)

local pulse = cc.glow:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local pa = pulse:CreateAnimation("Alpha")
pa:SetFromAlpha(1)
pa:SetToAlpha(0.25)
pa:SetDuration(0.45)

-- Pop-in when a proc fires: grows from 160 % to normal size.
local function addPop(frame)
	local g = frame:CreateAnimationGroup()
	local s = g:CreateAnimation("Scale")
	s:SetScaleFrom(1.6, 1.6)
	s:SetScaleTo(1, 1)
	s:SetDuration(0.18)
	s:SetSmoothing("OUT")
	frame.pop = g
end
addPop(cc)

-- Screen-edge flash.
local flash = UIParent:CreateTexture(nil, "BACKGROUND")
flash:SetAllPoints(UIParent)
flash:SetTexture("Interface\\FullScreenTextures\\LowHealth")
flash:SetBlendMode("ADD")
flash:SetVertexColor(BIG_COLOR[1] * 0.7, BIG_COLOR[2] * 0.8, 1)
flash:SetAlpha(0)
local flashAnim = flash:CreateAnimationGroup()
local fIn = flashAnim:CreateAnimation("Alpha")
fIn:SetFromAlpha(0)
fIn:SetToAlpha(0.8)
fIn:SetDuration(0.12)
fIn:SetOrder(1)
local fOut = flashAnim:CreateAnimation("Alpha")
fOut:SetFromAlpha(0.8)
fOut:SetToAlpha(0)
fOut:SetDuration(0.5)
fOut:SetOrder(2)

-- Proc icons, a row under the Clearcasting icon.
local slots = {}
local moving = false
local refreshMoveMode

local function toggleMute(spellId)
	if not spellId then return end
	db.muted[spellId] = not db.muted[spellId] or nil
	if refreshMoveMode then refreshMoveMode() end
end

for i = 1, MAX_PROCS do
	local f = CreateFrame("Frame", nil, anchor)
	f:SetSize(36, 36)
	f:Hide()
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetAllPoints()
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.border = f:CreateTexture(nil, "OVERLAY")
	f.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.border:SetBlendMode("ADD")
	f.border:SetVertexColor(1, 0.85, 0.3)
	f.border:SetPoint("CENTER")
	f.border:SetSize(68, 68)
	f.time = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	f.time:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	f.name:SetPoint("TOP", f.time, "BOTTOM", 0, -1)
	f.name:SetWidth(72)
	f.name:SetWordWrap(false)
	addPop(f)
	-- Mouse only in move mode, so the icons never block clicks in the middle of the screen.
	f:SetScript("OnMouseUp", function(self, button)
		if button == "RightButton" then toggleMute(self.spellId) end
	end)
	f:SetScript("OnEnter", function(self)
		if not self.spellId then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(spellName(self.spellId) or self.spellId)
		GameTooltip:AddLine(db.muted[self.spellId] and "Muted. Right-click: unmute" or "Right-click: mute", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
	slots[i] = f
end

local function layout()
	anchor:SetScale(db.scale / 100)
	anchor:ClearAllPoints()
	local p = db.point
	if p then anchor:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4]) else anchor:SetPoint("CENTER", 0, 160) end
end

---------------------------------------------------------------- state
local known = {}       -- auraInstanceID -> true, buffs seen in the last scan
local procs = {}       -- shown procs: { id, spellId, icon, expires }
local ccState          -- shown Clearcasting: { id, expires, count }
local baseline = true  -- next scan only learns what is there, without alerts
local restricted = false
local recentCasts = {} -- spell name -> time of your last cast
local knownTarget = {}  -- auraInstanceID -> true, your debuffs on the target in the last scan
local targetBaseline = true
local previewUntil

local function remember(spellId)
	db.seen[spellId] = time()
	-- keep the 12 newest
	local n, oldest, oldestT = 0, nil, math.huge
	for id, t in pairs(db.seen) do
		n = n + 1
		if t < oldestT then oldest, oldestT = id, t end
	end
	if n > 12 and oldest then db.seen[oldest] = nil end
end

local function isProc(a, now, onTarget)
	if not db.procs or db.muted[a.spellId] then return false end
	if a.watched then return true end
	local d = a.duration
	if not d or d <= 0 or d > db.maxDuration then return false end
	if db.onlyMine and not onTarget and not a.isFromPlayerOrPlayerPet then return false end
	local t = a.name and recentCasts[a.name]
	if t and now - t < 1.5 then return false end -- your own cast, not a proc
	return true
end

local function showCC(a, alert)
	local refreshed = ccState and ccState.id == a.auraInstanceID and a.expirationTime and ccState.expires
		and a.expirationTime > ccState.expires + 0.5
	-- -10: found while buff details are hidden, so the id is unknown
	local new = not ccState or (ccState.id ~= a.auraInstanceID and ccState.id ~= -10 and a.auraInstanceID ~= -10)
	ccState = { id = a.auraInstanceID, expires = a.expirationTime, count = a.applications }
	if a.icon then cc.icon:SetTexture(a.icon) end
	cc:Show()
	if not pulse:IsPlaying() then pulse:Play() end
	if alert and (new or refreshed) then
		cc.pop:Play()
		playSound(db.ccSound)
		if db.flash then flashAnim:Stop(); flashAnim:Play() end
	end
end

local function hideCC()
	ccState = nil
	pulse:Stop()
	cc:Hide()
end

local function drawProcs()
	if moving then return end
	for i = 1, MAX_PROCS do
		local f, p = slots[i], procs[i]
		if p then
			f.spellId = p.spellId
			f.icon:SetTexture(p.icon)
			f.icon:SetDesaturated(false)
			f.name:SetText("")
			f:ClearAllPoints()
			local n = #procs
			f:SetPoint("TOP", anchor, "BOTTOM", (i - (n + 1) / 2) * 44, -30)
			f:Show()
		else
			f.spellId = nil
			f:Hide()
		end
	end
end

local driver = CreateFrame("Frame")
driver:Hide()
local scanReactive -- defined with the reactive abilities

-- Reads one aura without ever touching hidden data: Forever hides most buff
-- details from addons in combat, and reading them raises an error.
-- Returns the aura, false for a hidden one, or nil at the end of the list.
local function readAura(unit, index, filter)
	if C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret then
		local ok, hidden = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, unit, index, filter)
		if ok and hidden == true then return false end
	end
	local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
	if not ok then return false end
	if not a then return nil end
	if issecret(a.spellId) or issecret(a.auraInstanceID) or issecret(a.duration)
		or issecret(a.expirationTime) or issecret(a.name) then
		return false
	end
	return a
end

-- Spells you can cast yourself (e.g. Regrowth) are never procs.
local function isOwnSpell(id)
	if C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id) then return true end
	return false
end

-- Clearcasting while buff details are hidden. Several ways, the first that works wins.
local overlayCC = false -- the game's own proc glow reported Clearcasting
local probeCost = {}    -- spell name -> highest cost seen
local PROBES = {        -- spells whose cost drops to 0 with Clearcasting
	DRUID = { 5221, 1082, 6807, 779, 8921, 5176, 5185, 774 },
	MAGE = { 116, 133, 5143, 1449, 120 },
	SHAMAN = { 403, 8042, 421, 331 },
}
local CAST_PROBES = {   -- spells whose cast time drops to 0 with the big proc
	WARLOCK = { 686 }, -- Shadow Bolt (Shadow Trance)
}
local probeCast = {}
local _, playerClass = UnitClass("player")

local function castTimeOf(name)
	if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
	local ok, info = pcall(C_Spell.GetSpellInfo, name)
	if not ok or type(info) ~= "table" then return nil end
	local t = info.castTime
	if t == nil or issecret(t) then return nil end
	return t
end

local function costOf(name)
	if not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
	local ok, costs = pcall(C_Spell.GetSpellPowerCost, name)
	if not ok or type(costs) ~= "table" or not costs[1] then return nil end
	local c = costs[1].cost
	if c == nil or issecret(c) then return nil end
	return c
end

local function hiddenCC()
	-- direct lookup by spell (works when Clearcasting itself is not hidden)
	for _, id in ipairs(CC_IDS) do
		local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if ok and a then
			return { auraInstanceID = -10,
				expirationTime = not issecret(a.expirationTime) and a.expirationTime or nil,
				applications = not issecret(a.applications) and a.applications or nil }, "spell id"
		end
	end
	if C_UnitAuras.GetAuraDataBySpellName then
		local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", CC_NAME, "HELPFUL")
		if ok and a then return { auraInstanceID = -10 }, "spell name" end
	end
	if overlayCC then return { auraInstanceID = -10 }, "proc glow" end
	-- ability costs: an ability that normally costs something is free
	for _, id in ipairs(PROBES[playerClass] or {}) do
		local name = spellName(id)
		if name and isOwnSpell(id) then
			local c = costOf(name)
			if c then
				if c > (probeCost[name] or 0) then probeCost[name] = c end
				if c == 0 and (probeCost[name] or 0) > 0 then return { auraInstanceID = -10 }, "free " .. name end
			end
		end
	end
	-- cast time: a spell that normally has one is instant
	for _, id in ipairs(CAST_PROBES[playerClass] or {}) do
		local name = spellName(id)
		if name and isOwnSpell(id) then
			local t = castTimeOf(name)
			if t then
				if t > (probeCast[name] or 0) then probeCast[name] = t end
				if t == 0 and (probeCast[name] or 0) > 0 then return { auraInstanceID = -10 }, "instant " .. name end
			end
		end
	end
	return nil
end

local lastSource
local function debugCC(source)
	if db.debug and source ~= lastSource then
		print("|cff4fb3ffProcFlare:|r Clearcasting " .. (source and ("on (" .. source .. ")") or "off"))
	end
	lastSource = source
end

-- Reactive abilities (Overpower, Revenge, Riposte, Mongoose Bite, Counterattack).
local reactives = {}      -- the class's abilities that are known: { id, name, icon, ids }
local reactiveById = {}   -- any rank id -> entry
local function buildReactives()
	reactives, reactiveById = {}, {}
	for _, ids in ipairs(REACTIVE[playerClass] or {}) do
		local isKnown = false
		for _, id in ipairs(ids) do if isOwnSpell(id) then isKnown = true end end
		local name = spellName(ids[1])
		if isKnown and name then
			local r = { id = ids[1], name = name, icon = spellIcon(ids[1]) }
			reactives[#reactives + 1] = r
			for _, id in ipairs(ids) do reactiveById[id] = r end
		end
	end
end

local isUsable = C_Spell and C_Spell.IsSpellUsable
local function reactiveOpen(r)
	if r.glow then return true end
	if not isUsable then return false end
	local ok, usable, noMana = pcall(isUsable, r.name)
	if not ok or issecret(usable) or issecret(noMana) then return false end
	-- noMana: the window is open, only rage or energy is missing
	return (usable or noMana) and true or false
end

scanReactive = function(now)
	for _, r in ipairs(reactives) do
		local open = db.procs and db.reactive and reactiveOpen(r)
		-- only a change counts: a client that always reports "usable" never alerts
		if not open then r.closedSeen = true end
		local idx
		for j, p in ipairs(procs) do
			if p.reactive and p.spellId == r.id then idx = j end
		end
		if open and r.closedSeen and not r.fired and not idx and not db.muted[r.id] then
			r.fired = true
			remember(r.id)
			table.insert(procs, 1, { id = "r" .. r.id, spellId = r.id, icon = r.icon, expires = now + REACTIVE_WINDOW, reactive = true })
			if procs[MAX_PROCS + 1] then procs[MAX_PROCS + 1] = nil end
			playSound(db.procSound)
			drawProcs()
			slots[1].pop:Play()
		elseif idx and (not open or procs[idx].expires < now) then
			table.remove(procs, idx)
			drawProcs()
		end
		if not open then r.fired = false end
	end
end

local function scan()
	if not db then return end
	local now = GetTime()
	local present, ccAura, ccSource, hidden = {}, nil, nil, 0
	for i = 1, 40 do
		local a = readAura("player", i, "HELPFUL")
		if a == nil then break end
		if a == false then
			hidden = hidden + 1
		elseif a then
			present[a.auraInstanceID] = a
			if CC_SET[a.spellId] or a.name == CC_NAME then ccAura, ccSource = a, "buff" end
		end
	end
	-- Known proc buffs of the class, asked for by spell id while details are hidden.
	if hidden > 0 and db.procs then
		-- skip what is already seen: in the list now, or before and not run out yet
		local bySpell = {}
		for _, a in pairs(present) do bySpell[a.spellId] = true end
		for _, a in pairs(known) do
			if not a.watched and a.expirationTime and a.expirationTime > now then bySpell[a.spellId] = true end
		end
		for _, id in ipairs(watchList) do
			if not bySpell[id] then
				local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
				if ok and a then
					local key = "w" .. id
					present[key] = { auraInstanceID = key, spellId = id, icon = spellIcon(id), name = spellName(id), watched = true,
						expirationTime = (not issecret(a.expirationTime)) and a.expirationTime or nil }
				end
			end
		end
	end
	if not ccAura then
		-- Look the other ways even when nothing seems hidden: some clients drop
		-- hidden buffs from the list without saying so.
		ccAura, ccSource = hiddenCC()
		if ccAura and ccState and ccState.id ~= -10 then ccAura.auraInstanceID = ccState.id end
	end
	restricted = hidden > 0
	debugCC(ccAura and ccSource)

	-- Procs: buffs that are new since the last scan. While buffs are hidden,
	-- the ones seen before are kept, so they do not count as new afterwards.
	local changed = false
	for id, a in pairs(present) do
		local same
		for _, p in ipairs(procs) do
			if p.spellId == a.spellId and not p.target and not p.reactive then same = p end
		end
		if same then
			-- the same buff, seen once by spell id and once in the list: keep one icon
			same.id = id
			if a.expirationTime then same.expires = a.expirationTime end
		elseif not known[id] and a ~= ccAura and not baseline and isProc(a, now) and not isOwnSpell(a.spellId) then
			remember(a.spellId)
			table.insert(procs, 1, { id = id, spellId = a.spellId, icon = a.icon, expires = a.expirationTime })
			if procs[MAX_PROCS + 1] then procs[MAX_PROCS + 1] = nil end
			changed = true
			playSound(db.procSound)
			slots[1].pendingPop = true
		end
	end
	for j = #procs, 1, -1 do
		local p = procs[j]
		-- procs on the target are handled with the target scan below
		if p.preview then
			if not previewUntil then table.remove(procs, j); changed = true end
		elseif not p.target and not p.reactive then
			if present[p.id] then
				p.expires = present[p.id].expirationTime
			-- a buff asked for by spell id is gone for sure once the game no longer has it
			elseif hidden == 0 or type(p.id) == "string" or (p.expires and p.expires < now) then
				table.remove(procs, j); changed = true
			end
		end
	end
	if changed then
		drawProcs()
		if slots[1].pendingPop then slots[1].pendingPop = nil; slots[1].pop:Play() end
	end

	if db.clearcasting and ccAura then
		showCC(ccAura, not baseline)
	elseif not previewUntil then
		hideCC()
	end

	-- Debuff procs on your target (e.g. Icy Chill, Spell Vulnerability).
	local tPresent, tHidden = {}, false
	if db.procs and db.targetProcs and UnitExists("target") then
		for j = 1, 40 do
			local a = readAura("target", j, "HARMFUL|PLAYER")
			if a == nil then break end
			if a == false then tHidden = true elseif a then tPresent[a.auraInstanceID] = a end
		end
	end
	for id, a in pairs(tPresent) do
		if not knownTarget[id] and not targetBaseline and isProc(a, now, true) and not isOwnSpell(a.spellId) then
			remember(a.spellId)
			table.insert(procs, 1, { id = id, spellId = a.spellId, icon = a.icon, expires = a.expirationTime, target = true })
			if procs[MAX_PROCS + 1] then procs[MAX_PROCS + 1] = nil end
			playSound(db.procSound)
			drawProcs()
			slots[1].pop:Play()
		end
	end
	for j = #procs, 1, -1 do
		local p = procs[j]
		if p.target and not tPresent[p.id] and (not tHidden or (p.expires and p.expires < now)) then
			table.remove(procs, j); drawProcs()
		elseif p.target and tPresent[p.id] then
			p.expires = tPresent[p.id].expirationTime
		end
	end
	if tHidden then
		for id, a in pairs(knownTarget) do if not tPresent[id] then tPresent[id] = a end end
	end
	knownTarget = tPresent
	targetBaseline = false

	scanReactive(now)

	if hidden > 0 then
		for id, a in pairs(known) do if not present[id] then present[id] = a end end
	end
	known = present
	baseline = false
	if ccState or #procs > 0 then driver:Show() end
end

-- Countdowns, ten times a second, and only while something is shown.
-- Twice a second the buffs are checked again: the game does not always report
-- a used-up Clearcasting, e.g. when the target dies from the same hit.
local elapsedSum, recheckSum = 0, 0
driver:SetScript("OnUpdate", function(self, elapsed)
	elapsedSum = elapsedSum + elapsed
	if elapsedSum < 0.1 then return end
	recheckSum = recheckSum + elapsedSum
	elapsedSum = 0
	local now = GetTime()
	if previewUntil and now > previewUntil then
		previewUntil = nil
		pcall(scan)
	elseif recheckSum >= 0.5 and not previewUntil then
		recheckSum = 0
		pcall(scan)
	end
	-- An expired buff never stays on screen, even if no update arrives.
	if ccState and ccState.expires and ccState.expires > 0 and ccState.expires < now and not previewUntil then
		hideCC()
	end
	if ccState then
		local e = ccState.expires
		cc.time:SetText(e and e > now and string.format("%.0f", e - now) or "")
		cc.count:SetText(ccState.count and ccState.count > 1 and ccState.count or "")
	end
	for i, p in ipairs(procs) do
		local e = p.expires
		slots[i].time:SetText(e and e > now and string.format("%.1f", e - now) or "")
	end
	if not ccState and #procs == 0 and not previewUntil then self:Hide() end
end)

---------------------------------------------------------------- preview, move mode
local function preview()
	previewUntil = GetTime() + 6
	showCC({ auraInstanceID = -1, expirationTime = GetTime() + 15, applications = 1, icon = spellIcon(BIG_PROC.id) }, true)
	table.insert(procs, 1, { id = -2, spellId = PREVIEW_PROC, icon = spellIcon(PREVIEW_PROC), expires = GetTime() + 15, preview = true })
	if procs[MAX_PROCS + 1] then procs[MAX_PROCS + 1] = nil end
	drawProcs()
	slots[1].pop:Play()
	C_Timer.After(0.6, function() playSound(db.procSound) end)
	driver:Show()
end

-- Move mode: the frame can be dragged, and the procs seen recently are shown
-- as icons; right-click mutes or unmutes one.
refreshMoveMode = function()
	if not moving then return end
	local list = {}
	for id, t in pairs(db.seen) do list[#list + 1] = { id = id, t = t } end
	for id in pairs(db.muted) do
		if not db.seen[id] then list[#list + 1] = { id = id, t = 0 } end
	end
	table.sort(list, function(a, b) return a.t > b.t end)
	if #list == 0 then list[1] = { id = PREVIEW_PROC } end
	for i = 1, MAX_PROCS do
		local f, e = slots[i], list[i]
		if e then
			f.spellId = e.id
			f.icon:SetTexture(spellIcon(e.id))
			f.icon:SetDesaturated(db.muted[e.id] and true or false)
			f.time:SetText(db.muted[e.id] and "|cffff4040muted|r" or "")
			f.name:SetText(spellName(e.id) or "")
			f:ClearAllPoints()
			local n = math.min(#list, MAX_PROCS)
			f:SetPoint("TOP", anchor, "BOTTOM", (i - (n + 1) / 2) * 76, -30)
			f:EnableMouse(true)
			f:Show()
		else
			f:Hide()
		end
	end
end

local doneButton
local function setMoving(on)
	moving = on
	doneButton:SetShown(on)
	anchor:EnableMouse(on)
	moveBg:SetShown(on)
	moveText:SetShown(on)
	if on then
		cc:Show()
		refreshMoveMode()
	else
		for _, f in ipairs(slots) do
			f:EnableMouse(false)
			f.name:SetText("")
			f.time:SetText("")
		end
		if not ccState then cc:Hide() end
		drawProcs()
	end
end

doneButton = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
doneButton:SetSize(80, 22)
doneButton:SetPoint("BOTTOM", moveText, "TOP", 0, 4)
doneButton:SetText("Done")
doneButton:SetScript("OnClick", function() setMoving(false) end)
doneButton:Hide()

---------------------------------------------------------------- options window, minimap button
local LDBIcon

local function applyMinimap()
	if not LDBIcon then return end
	db.minimap = db.minimap or {}
	db.minimap.hide = not db.showMinimap
	if db.showMinimap then LDBIcon:Show(ADDON) else LDBIcon:Hide(ADDON) end
end

-- Own window instead of a page in the game's options: drag it anywhere, it stays open
-- while you play, and every change shows at once.
local win
local function buildWindow()
	local UI = _G.LibStub("BencepoUI-1.0")
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	win = UI:CreateWindow({
		name = "ProcFlareOptionsFrame", title = ADDON, width = 520, height = 430,
		subtitle = (version and not version:find("@")) and version or nil,
		accent = { 0.31, 0.70, 1, 1 }, db = db, posKey = "optPos",
	})
	local function opt(key, onChange)
		return function() return db[key] end, function(v)
			db[key] = v
			if onChange then onChange(v) end
		end
	end

	-- left: what is shown
	local L = 16
	win:Header(L, -48, "Alerts")
	win:Check(L, -72, BIG_PROC.label .. " alert", "Big pulsing icon while " .. BIG_PROC.label
		.. " is up (Clearcasting for druids, mages and shamans, Shadow Trance from Nightfall for warlocks).",
		opt("clearcasting", function() pcall(scan) end))
	win:Check(L, -96, "Screen flash", "Short blue flash at the screen edges when Clearcasting procs.", opt("flash"))
	win:Check(L, -120, "Other procs", "Small icons with countdown for weapon, trinket and talent procs.", opt("procs"))
	win:Check(L, -144, "Procs on the target", "Debuffs your weapon or talents put on your target, e.g. Icy Chill or Spell Vulnerability.",
		opt("targetProcs", function() pcall(scan) end))
	win:Check(L, -168, "Only my own procs", "Ignore short buffs other players put on you.", opt("onlyMine"))
	win:Check(L, -192, "Reactive abilities", "Overpower and Revenge (warrior), Riposte (rogue), Mongoose Bite and Counterattack (hunter): "
		.. "shown for the few seconds after a dodge, parry or block opens them. Only your class's ones.", opt("reactive", function() pcall(scan) end))
	win:Check(L, -216, "Minimap button", "Show the ProcFlare button at the minimap.", opt("showMinimap", applyMinimap))
	win:Slider(L, -248, "Longest proc", 5, 120, 5, function() return db.maxDuration end,
		function(v) db.maxDuration = v end, "Buffs up to this many seconds count as procs.", 170,
		function(v) return v .. " s" end)
	win:Slider(L, -288, "Size", 50, 200, 10, function() return db.scale end,
		function(v) db.scale = v; layout() end, "Size of the icons in percent.", 170,
		function(v) return v .. " %" end)

	-- right: sounds
	local R = 270
	local packItems = {}
	for i, p in ipairs(PACKS) do packItems[#packItems + 1] = { i, p.name } end
	win:Header(R, -48, "Sound")
	win:Dropdown(R, -70, "Sound pack", 220, packItems, function() return db.pack or 1 end, function(v)
		local p = PACKS[v]
		if not p then return end
		db.pack, db.ccSound, db.procSound = v, p.cc, p.proc
		playSound(p.cc)
	end, "Melee: drums, horns and steel. Caster: arcane, frost and fire. Sets both sounds below; each can still be changed.")
	win:Dropdown(R, -116, "Clearcasting sound", 220, SOUNDS, function() return db.ccSound end,
		function(v) db.ccSound = v; playSound(v) end, "Sound when Clearcasting procs.")
	win:Dropdown(R, -162, "Proc sound", 220, SOUNDS, function() return db.procSound end,
		function(v) db.procSound = v; playSound(v) end, "Sound when another proc fires.")
	win:Slider(R, -210, "Volume", 25, 100, 25, function() return db.volume end,
		function(v) db.volume = v; playSound(db.ccSound) end,
		"Volume of ProcFlare's own sounds. The game's volume slider for the sound channel applies on top.", 170,
		function(v) return v .. " %" end)
	win:Dropdown(R, -250, "Sound channel", 220, CHANNELS, function() return db.channel end,
		function(v) db.channel = v; playSound(db.ccSound) end,
		"Which of the game's volume sliders (System > Audio) controls ProcFlare's sounds.")

	-- bottom: preview and position
	local prev = win:Button("Preview", 110, preview, "Shows Clearcasting and a weapon proc for 6 seconds, with sounds.")
	prev:SetPoint("TOPLEFT", L, -340)
	local move = win:Button("Move icons", 130, function() setMoving(not moving) end,
		"Drag the icons where you want them. Your recent procs are shown: right-click one to mute or unmute it.")
	move:SetPoint("LEFT", prev, "RIGHT", 8, 0)
	win:OnRefresh(function() move:SetText(moving and "Done moving" or "Move icons") end)
	doneButton:HookScript("OnClick", function() win:Refresh() end)
	local unmute = win:Button("Unmute all", 110, function() wipe(db.muted); refreshMoveMode() end, "Alerts for every proc again.")
	unmute:SetPoint("LEFT", move, "RIGHT", 8, 0)
	win:Text(L, -378, "Muting: click \"Move icons\", then right-click a proc. Changes apply at once; the window stays open while you play.", 488)
end

local function openOptions()
	if not win then buildWindow() end
	win:Toggle()
end

-- The game's options only point to the window, so ProcFlare is still found there.
local function registerSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local category, layoutCat = Settings.RegisterVerticalLayoutCategory(ADDON)
	if layoutCat and CreateSettingsButtonInitializer then
		layoutCat:AddInitializer(CreateSettingsButtonInitializer("ProcFlare has its own window", "Open", function()
			if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			if not win then buildWindow() end
			win:Show()
		end, "Opens the ProcFlare window. It can be dragged anywhere and stays open while you play.", true))
	end
	Settings.RegisterAddOnCategory(category)
end

local function registerMinimap()
	local LibStub = _G.LibStub
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and LDBIcon) then return end
	local obj = LDB:NewDataObject(ADDON, {
		type = "launcher",
		text = ADDON,
		icon = "Interface\\AddOns\\ProcFlare\\Icons\\minimap",
		OnClick = function(_, button)
			if button == "RightButton" then preview()
			elseif IsShiftKeyDown() then setMoving(not moving)
			else openOptions() end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine(ADDON)
			tt:AddLine("|cffffffffLeft-click:|r options", 0.8, 0.8, 0.8)
			tt:AddLine("|cffffffffShift-click:|r move / mute procs", 0.8, 0.8, 0.8)
			tt:AddLine("|cffffffffRight-click:|r preview", 0.8, 0.8, 0.8)
			if restricted then tt:AddLine("Buff details are hidden from addons right now, new procs may be missed.", 1, 0.5, 0.3, true) end
		end,
	})
	db.minimap = db.minimap or {}
	db.minimap.hide = not db.showMinimap
	LDBIcon:Register(ADDON, obj, db.minimap)
end

-- Entry in the game's addon menu (the button next to the minimap).
function ProcFlare_OnCompartmentClick(_, button)
	if button == "RightButton" then preview() else openOptions() end
end

SLASH_PROCFLARE1 = "/procflare"
SLASH_PROCFLARE2 = "/pfl"
SlashCmdList.PROCFLARE = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "test" then preview()
	elseif msg == "debug" then
		db.debug = not db.debug
		print("|cff4fb3ffProcFlare:|r debug " .. (db.debug and "on" or "off"))
	elseif msg == "move" then setMoving(not moving)
	else openOptions() end
end

---------------------------------------------------------------- events
local scanQueued = false
local usablePending = false
local function queueScan()
	if scanQueued then return end
	scanQueued = true
	C_Timer.After(0, function()
		scanQueued = false
		local ok, err = pcall(scan)
		if not ok and db and db.debug then print("|cff4fb3ffProcFlare:|r " .. tostring(err)) end
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1, _, arg3)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		ProcFlareDB = ProcFlareDB or {}
		db = ProcFlareDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		-- 0.1.6: the old default game sounds move to ProcFlare's own sounds once.
		if not db.ownSounds then
			if db.ccSound == 8959 then db.ccSound = -1 end
			if db.procSound == 3175 then db.procSound = -2 end
			db.ownSounds = true
		end
		db.muted = db.muted or {}
		db.seen = db.seen or {}
		layout()
		registerSettings()
		registerMinimap()
		self:RegisterUnitEvent("UNIT_AURA", "player", "target")
		self:RegisterEvent("PLAYER_TARGET_CHANGED")
		self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		-- The game's own proc glow and ability usability change with Clearcasting.
		for _, e in ipairs({ "SPELL_ACTIVATION_OVERLAY_SHOW", "SPELL_ACTIVATION_OVERLAY_HIDE",
			"SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "SPELL_UPDATE_USABLE",
			"ACTIONBAR_UPDATE_USABLE", "SPELLS_CHANGED",
			"PLAYER_REGEN_DISABLED" }) do
			pcall(self.RegisterEvent, self, e)
		end
	elseif event == "SPELLS_CHANGED" then
		buildReactives()
	elseif event == "PLAYER_ENTERING_WORLD" then
		buildReactives()
		baseline = true
		queueScan()
		-- 0.2.0: pick the sound pack once from class and talents, unless sounds were picked by hand.
		if not db.packPicked then
			C_Timer.After(3, function()
				if db.packPicked then return end
				db.packPicked = true
				db.pack = guessPack()
				local untouched = { [8959] = true, [3175] = true, [-1] = true, [-2] = true }
				if untouched[db.ccSound] then db.ccSound = PACKS[db.pack].cc end
				if untouched[db.procSound] then db.procSound = PACKS[db.pack].proc end
			end)
		end
	elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		queueScan()
	elseif event == "SPELL_UPDATE_USABLE" or event == "ACTIONBAR_UPDATE_USABLE" then
		-- Fires on every resource change. Only needed to see the big proc through free or
		-- instant spells and the reactive abilities: one scan 0.1 s after the first of a burst.
		if (PROBES[playerClass] or CAST_PROBES[playerClass] or #reactives > 0) and not usablePending then
			usablePending = true
			C_Timer.After(0.1, function()
				usablePending = false
				queueScan()
			end)
		end
	elseif event == "SPELL_ACTIVATION_OVERLAY_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		if db.debug then print("|cff4fb3ffProcFlare:|r " .. event .. " " .. tostring(not issecret(arg1) and arg1 or "?")) end
		if arg1 and not issecret(arg1) and (CC_SET[arg1] or spellName(arg1) == CC_NAME) then overlayCC = true end
		if arg1 and not issecret(arg1) and reactiveById[arg1] then reactiveById[arg1].glow = true end
		queueScan()
	elseif event == "SPELL_ACTIVATION_OVERLAY_HIDE" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		if not arg1 or issecret(arg1) or CC_SET[arg1] or spellName(arg1) == CC_NAME then overlayCC = false end
		if arg1 and not issecret(arg1) and reactiveById[arg1] then reactiveById[arg1].glow = nil
		elseif not arg1 or issecret(arg1) then for _, r in ipairs(reactives) do r.glow = nil end end
		queueScan()
	elseif event == "PLAYER_TARGET_CHANGED" then
		targetBaseline = true
		knownTarget = {}
		for j = #procs, 1, -1 do if procs[j].target then table.remove(procs, j) end end
		drawProcs()
		queueScan()
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg3 and not issecret(arg3) then
			local name = spellName(arg3)
			if name then recentCasts[name] = GetTime() end
		end
	end
end)
