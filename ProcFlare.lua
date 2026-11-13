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
	flash = true,        -- screen-edge flash on Clearcasting
	scale = 100,         -- size in percent
	showMinimap = true,  -- minimap button
}

-- Clearcasting: Omen of Clarity (druid), Arcane Concentration (mage), Elemental Focus (shaman).
local CC_IDS = { 16870, 12536, 16246 }
local CC_SET = {}
for _, id in ipairs(CC_IDS) do CC_SET[id] = true end

-- ProcFlare's own sounds (the same tones as on bencepo.github.io/procflare).
local SOUND_FILES = {
	[-1] = "Interface\\AddOns\\ProcFlare\\Sounds\\clearcasting.ogg",
	[-2] = "Interface\\AddOns\\ProcFlare\\Sounds\\proc.ogg",
}

local SOUNDS = {
	{ 0, "None" },
	{ -1, "ProcFlare chime" },
	{ -2, "ProcFlare ping" },
	{ 8959, "Raid warning" },
	{ 8960, "Ready check" },
	{ 12889, "Alarm clock" },
	{ 3175, "Map ping" },
	{ 18019, "Toast" },
}

local MAX_PROCS = 6
local PREVIEW_PROC = 20007 -- Holy Strength (Crusader enchant)

local db

local function spellName(id) return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) end
local function spellIcon(id) return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) end
local function playSound(id)
	if not id or id == 0 then return end
	if SOUND_FILES[id] then PlaySoundFile(SOUND_FILES[id], "Master") elseif id > 0 then PlaySound(id, "Master") end
end

local CC_NAME = spellName(16870) or "Clearcasting"

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
cc.icon:SetTexture(spellIcon(16870))
cc.glow = cc:CreateTexture(nil, "OVERLAY")
cc.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
cc.glow:SetBlendMode("ADD")
cc.glow:SetVertexColor(0.45, 0.75, 1)
cc.glow:SetPoint("CENTER")
cc.glow:SetSize(124, 124)
cc.label = cc:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
cc.label:SetPoint("TOP", cc, "BOTTOM", 0, -4)
cc.label:SetTextColor(0.55, 0.8, 1)
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
flash:SetVertexColor(0.3, 0.6, 1)
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
local _, playerClass = UnitClass("player")

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
	return nil
end

local lastSource
local function debugCC(source)
	if db.debug and source ~= lastSource then
		print("|cff4fb3ffProcFlare:|r Clearcasting " .. (source and ("on (" .. source .. ")") or "off"))
	end
	lastSource = source
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
		if not known[id] and a ~= ccAura and not baseline and isProc(a, now) and not isOwnSpell(a.spellId) then
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
		elseif not p.target then
			if present[p.id] then
				p.expires = present[p.id].expirationTime
			elseif hidden == 0 or (p.expires and p.expires < now) then
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
	showCC({ auraInstanceID = -1, expirationTime = GetTime() + 15, applications = 1, icon = spellIcon(16870) }, true)
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
local category
local LDBIcon

local function openOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	end
end

local function applyMinimap()
	if not LDBIcon then return end
	db.minimap = db.minimap or {}
	db.minimap.hide = not db.showMinimap
	if db.showMinimap then LDBIcon:Show(ADDON) else LDBIcon:Hide(ADDON) end
end

local function registerSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	local layoutCat
	category, layoutCat = Settings.RegisterVerticalLayoutCategory(ADDON)
	local function checkbox(key, label, tooltip, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "PROCFLARE_" .. key:upper(), key, db,
			Settings.VarType.Boolean, label, DEFAULTS[key])
		Settings.CreateCheckbox(category, setting, tooltip)
		if onChange then setting:SetValueChangedCallback(onChange) end
	end
	local function slider(key, label, min, max, step, tooltip, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "PROCFLARE_" .. key:upper(), key, db,
			Settings.VarType.Number, label, DEFAULTS[key])
		local opts = Settings.CreateSliderOptions(min, max, step)
		if MinimalSliderWithSteppersMixin and opts.SetLabelFormatter then
			opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, setting, opts, tooltip)
		if onChange then setting:SetValueChangedCallback(onChange) end
	end
	local function soundDropdown(key, label, tooltip)
		local dropdown = Settings.CreateDropdown or Settings.CreateDropDown
		if not (dropdown and Settings.CreateControlTextContainer) then return end
		local setting = Settings.RegisterAddOnSetting(category, "PROCFLARE_" .. key:upper(), key, db,
			Settings.VarType.Number, label, DEFAULTS[key])
		dropdown(category, setting, function()
			local c = Settings.CreateControlTextContainer()
			for _, s in ipairs(SOUNDS) do c:Add(s[1], s[2]) end
			return c:GetData()
		end, tooltip)
		setting:SetValueChangedCallback(function(_, value) playSound(value) end)
	end

	checkbox("clearcasting", "Clearcasting alert", "Big pulsing icon while Clearcasting is up.", function() pcall(scan) end)
	soundDropdown("ccSound", "Clearcasting sound", "Sound when Clearcasting procs.")
	checkbox("flash", "Screen flash", "Short blue flash at the screen edges when Clearcasting procs.")
	checkbox("procs", "Other procs", "Small icons with countdown for weapon, trinket and talent procs.")
	soundDropdown("procSound", "Proc sound", "Sound when another proc fires.")
	checkbox("targetProcs", "Procs on the target", "Debuffs your weapon or talents put on your target, e.g. Icy Chill or Spell Vulnerability.", function() pcall(scan) end)
	checkbox("onlyMine", "Only my own procs", "Ignore short buffs other players put on you.")
	slider("maxDuration", "Longest proc", 5, 120, 5, "Buffs up to this many seconds count as procs.")
	slider("scale", "Size", 50, 200, 10, "Size of the icons in percent.", layout)
	checkbox("showMinimap", "Minimap button", "Show the ProcFlare button at the minimap.", applyMinimap)

	if layoutCat and CreateSettingsButtonInitializer then
		layoutCat:AddInitializer(CreateSettingsButtonInitializer("Preview", "Show", preview,
			"Shows Clearcasting and a weapon proc for 6 seconds, with sounds.", true))
		layoutCat:AddInitializer(CreateSettingsButtonInitializer("Position and muted procs", "Move",
			function() setMoving(true) end,
			"Drag the icons where you want them. Your recent procs are shown: right-click one to mute or unmute it.", true))
		layoutCat:AddInitializer(CreateSettingsButtonInitializer("Muted procs", "Unmute all",
			function() wipe(db.muted); refreshMoveMode() end, "Alerts for every proc again.", true))
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
			"PLAYER_REGEN_DISABLED" }) do
			pcall(self.RegisterEvent, self, e)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		baseline = true
		queueScan()
	elseif event == "UNIT_AURA" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
		queueScan()
	elseif event == "SPELL_UPDATE_USABLE" then
		-- Fires on every resource change. Only needed to see Clearcasting through free spell
		-- costs (classes with Clearcasting): one scan 0.2 s after the first of a burst.
		if PROBES[playerClass] and not usablePending then
			usablePending = true
			C_Timer.After(0.2, function()
				usablePending = false
				queueScan()
			end)
		end
	elseif event == "SPELL_ACTIVATION_OVERLAY_SHOW" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
		if db.debug then print("|cff4fb3ffProcFlare:|r " .. event .. " " .. tostring(not issecret(arg1) and arg1 or "?")) end
		if arg1 and not issecret(arg1) and (CC_SET[arg1] or spellName(arg1) == CC_NAME) then overlayCC = true end
		queueScan()
	elseif event == "SPELL_ACTIVATION_OVERLAY_HIDE" or event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
		if not arg1 or issecret(arg1) or CC_SET[arg1] or spellName(arg1) == CC_NAME then overlayCC = false end
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
