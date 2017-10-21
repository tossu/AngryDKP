-----------------------------------------------------------------------------
-- Copyright Tohveli @ Chamber of Aspects (miica @ IRCnet/Freenode)
-----------------------------------------------------------------------------

-- /script GuildRanks(); helps with RANKS
local ALLOWED_RANKS = {
	[0] =1,-- >:(
	[1] =1, -- Kenraali
	[2] =1, -- Raid Leader
	[3] =1, -- Veteraani
	[4] =1, -- Nostoväki
	[5] =1, -- Toveri
}

-- Gives points to RAID and STANBY members (removing or addin one will change UI too)
local REWARDS = {
   ["Start"] = 10,
   ["Hour"] = 1,
   ["Progress Hour"] = 15,
   ["Boss"] = 5,
   ["Progress Boss"] = 15,
   ["Ending"] = 5,
}

-- What kinda loot will open in lootframe
local LOOT_RARITY = 4 -- EPIC
--0. Poor (gray): Broken I.W.I.N. Button
--1. Common (white): Archmage Vargoth's Staff
--2. Uncommon (green): X-52 Rocket Helmet
--3. Rare / Superior (blue): Onyxia Scale Cloak
--4. Epic (purple): Talisman of Ephemeral Power
--5. Legendary (orange): Fragment of Val'anyr
--6. Artifact (golden yellow): The Twin Blades of Azzinoth
--7. Heirloom (light yellow): Bloodied Arcanite Reaper

local IGNORED_ITEMS = {
	["Emblem of Frost"] =1,
	["Emblem of Valor"] =1,
	["Emblem of Heroism"] =1,
	["Emblem of Conquest"] =1,
	["Emblem of Triumph"] =1,
	["Shadowfrost Shard"] =1,
};

local GUILD_MEMBERS_SORT_ORDER = "dkp"
local MINIUM_BID_RAISE = 5
local MAX_LVL = 85;
--
-- Dont touch after this.
--
local MASTER_FONT = {[[Interface\AddOns\AngryDKP4\media\uf_font.ttf]], 15, "OUTLINE"}
local BACKGROUND_ALPHA = 0.75
local MASTER_COLOR = {245/255,140/255,186/255,1}
local DISABLED_COLOR = {102/255,102/255,102/255,1}

local BORDER_COLOR = { .15, .15, .15, 1}; 
local BG_COLOR = { .05, .05, .05, 1 };
	
local CLASS_COLORS = {
	["Death Knight"] = {196/255,30/255,60/255},
	["Druid"] = {255/255,125/255,10/255},
	["Hunter"] = {171/255,214/255,116/255},
	["Mage"] = {104/255,205/255,255/255},
	["Paladin"] = {245/255,140/255,186/255},
	["Priest"] = {212/255,212/255,212/255},
	["Rogue"] = {255/255,243/255,82/255},
	["Shaman"] = {41/255,79/255,155/255},
	["Warlock"] = {148/255,130/255,201/255},
	["Warrior"] = {199/255,156/255,110/255},
}
-- no need to use string data in roster (better to have 20 here than 200 in roster)
local CLASS = {
	["Death Knight"] = 0,
	["Druid"] = 1,
	["Hunter"] = 2,
	["Mage"] = 3,
	["Paladin"] = 4,
	["Priest"] = 5,
	["Rogue"] = 6,
	["Shaman"] = 7,
	["Warlock"] = 8,
	["Warrior"] = 9,
	[0] = "Death Knight",
	[1] = "Druid",
	[2] = "Hunter",
	[3] = "Mage",
	[4] = "Paladin",
	[5] = "Priest",
	[6] = "Rogue",
	[7] = "Shaman",
	[8] = "Warlock",
	[9] = "Warrior",
}

local RAID_MEMBERS = {}
local BIDS = {}
local GUILD_MEMBERS = {}
local GUILD_MEMBERS_AMOUNT = nil
local LAST_LOOTED = ""
local DKP_LOCK = false

-- Saved Variables
if(STANDBY == nil) then STANDBY = {} end
if(SHOW_LOOTFRAMES == nil) then SHOW_LOOTFRAMES = true end
if(SHOW_LOOTS == nil) then SHOW_LOOTS = true end

--
-- Public Functions
--
function GuildRanks()
	for i=1, GuildControlGetNumRanks() do
		print("["..(i-1).."] ".. GuildControlGetRankName(i))
	end
end

function ResetNotes()
	for i=1, GetNumGuildMembers(true) do
		local _,_,rankindex,level = GetGuildRosterInfo(i)
		if(level == MAX_LVL and ALLOWED_RANKS[rankindex]) then
			GuildRosterSetPublicNote(i, tostring(0))
		end
	end
	ChatThrottleLib:SendAddonMessage("ALERT", "AngryDKP", "UpdateRoster", "GUILD")
end

local function round(num, idp)
	local mult = 10^(idp or 0)
	return math.floor(num * mult + 0.5) / mult
end

-- split message
local function SendMessage(type, msg, to)
	local l = string.len(msg)
	if l <= (255-10) then
		ChatThrottleLib:SendChatMessage("NORMAL", "AngryDKP", msg, type, nil, to)
		return
	end
	local lines = round(l/255, 0)+1
	for i=0, lines do
		local message = string.sub(msg, i*(255-9), (i*(255-10))+255-10)
		ChatThrottleLib:SendChatMessage("NORMAL", "AngryDKP", message, type, nil, to)
	end
end

local function isML()
	if not UnitInRaid("player") then return; end
	if GetLootMethod() == "master" then
		if UnitName("player") == GetRaidRosterInfo(select(3,GetLootMethod())) then
			return true
		end
		return false
      	end
end

--
-- DKP FUNCTIONS
--
local function GiveDKP(player, amount, reason)
	if(DKP_LOCK) then
		print("[DKP] Roster is outdated.")
		return false
	end

	local member = GUILD_MEMBERS[player]
	if(member) then
		SendMessage("GUILD", "[DKP] "..amount.." to "..player.." ("..reason..")")
		GuildRosterSetPublicNote(member.index, tostring(tonumber(member.dkp)+tonumber(amount)))
		ChatThrottleLib:SendAddonMessage("ALERT", "AngryDKP", "UpdateRoster", "GUILD")
		DKP_LOCK = true
		GuildRoster()
	end
end

local function RaidAndStanbyDKP(amount, reason)
	if(DKP_LOCK or not UnitInRaid("player")) then
		print("[DKP] Roster is outdated or not in raid.")
		return false
	end
   
	local raidlist = nil
	local standbylist = nil
	for name,member in pairs(GUILD_MEMBERS) do
		if(RAID_MEMBERS[name] or STANDBY[name]) then
			if(RAID_MEMBERS[name]) then
				raidlist = (not raidlist and name) or raidlist.." "..name
			elseif(STANDBY[name]) then
				standbylist = (not standbylist and name) or standbylist.." "..name
			end
			GuildRosterSetPublicNote(member.index, tostring(tonumber(member.dkp)+tonumber(amount)))
		end
	end
	if(raidlist and not standbylist) then
		 SendMessage("GUILD","[DKP] "..amount.." to raid("..raidlist..") ("..reason..")")
	elseif(raidlist and standbylist) then
		 SendMessage("GUILD","[DKP] "..amount.." to raid("..raidlist..") standby("..standbylist..") ("..reason..")")
	end
	ChatThrottleLib:SendAddonMessage("ALERT", "AngryDKP", "UpdateRoster", "GUILD")
	
	DKP_LOCK = true
	GuildRoster()
end


local function CheckedDKP(amount, reason)
	if(DKP_LOCK) then
		print("[DKP] Raid roster is outdated.")
      		return false
	end

	local list = nil;
	for i=1, GUILD_MEMBERS_AMOUNT do
		local button = _G["GuildMembersCheckButtons"..i]
		if(button.name ~= "" and button:GetChecked()) then
			local member = GUILD_MEMBERS[button.name]
			list = (not list and button.name) or list.." "..button.name
			GuildRosterSetPublicNote(member.index, tostring(tonumber(member.dkp)+tonumber(amount)))
		end
   	end
   	if(list) then
		SendMessage("GUILD", "[DKP] "..amount.." to players("..list..") ("..reason..")")
		ChatThrottleLib:SendAddonMessage("ALERT", "AngryDKP", "UpdateRoster", "GUILD")
		DKP_LOCK = true
		GuildRoster()
	end
end

--
-- LOLZOR?
--
local SetTemplate = function(f)
	f:SetBackdrop({
	  bgFile = [[Interface\AddOns\AngryDKP4\media\blank]], 
	  edgeFile = [[Interface\AddOns\AngryDKP4\media\blank]], 
	  tile = false, tileSize = 0, edgeSize = 1, 
	  insets = { left = -1, right = -1, top = -1, bottom = -1}
	})
	f:SetBackdropColor(unpack(BG_COLOR))
	f:SetBackdropBorderColor(unpack(BORDER_COLOR))
end

local EditBox = function(parent,width,height)
	local result = CreateFrame("EditBox", nil, parent)
	result:SetAutoFocus(false)
	result:SetMultiLine(false)
	result:SetSize(width,height)
	result:SetMaxLetters(255)
	result:SetTextInsets(3,0,0,0)
	result:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	result:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
   
	SetTemplate(result)
	result:SetFontObject(GameFontHighlight)

	return result
end

local Frame = function(name,labeltext,width,height)
	local result = CreateFrame("Frame", name, UIParent, nil)
	result:SetMovable(true)
	result:SetSize(width,height)
	
	SetTemplate(result)
	
	-- LABEL
	local button = CreateFrame("Button", nil, result, nil)
	button:SetPoint("TOPLEFT", 0, 17)
	button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
	button:SetScript("OnMouseUp", function(self) result:StopMovingOrSizing() end)
	button:SetScript("OnMouseDown", function(self, button) result:StartMoving() end)
	local label = button:CreateFontString( nil, "OVERLAY", nil )
	label:SetFont(unpack(MASTER_FONT))
	label:SetText(labeltext)
	label:SetTextColor(unpack(MASTER_COLOR))
	button:SetSize(label:GetWidth(),label:GetHeight())
	button:SetFontString(label)
	
	-- CLOSE BUTTON
	local button = CreateFrame("Button", nil, result, nil)
	button:SetPoint("TOPRIGHT", 0, 17)
	button:SetScript("OnClick", function(self) result:Hide() end)
   
	local label = button:CreateFontString(nil, "OVERLAY", nil)
	label:SetFont(unpack(MASTER_FONT))
	label:SetText("CLOSE")
	button:SetSize(label:GetWidth(),label:GetHeight())
	button:SetFontString(label)
	
	return result
end

--
-- LOOTFRAME
--
local function LootFrame(receiver, itemlink, amount)
	if(receiver == nil or itemlink == nil or amount == nil) then
		return
	end
	local itemName,itemLink,_,_,_,_,_,_,_,itemTexture = GetItemInfo(itemlink);  
   
	local LootFrame = Frame(nil,"LOOT",200,60)
	LootFrame:SetPoint("CENTER", UIParent, "CENTER")
   
	-- ICON
	local Icon = CreateFrame("Button", nil, LootFrame, nil)
	Icon:SetPoint("TOPLEFT")
	Icon:SetSize(40,40)
	Icon:SetScript("OnEnter",
		function()
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
			GameTooltip:SetHyperlink(itemLink)
			GameTooltip:Show()
		end)
	Icon:SetScript("OnLeave", function() GameTooltip:Hide(); end)
	local background = Icon:CreateTexture( nil, "BACKGROUND", nil)
	background:SetTexture(itemTexture)
	background:SetPoint("TOPLEFT", Icon, "TOPLEFT", 5, -5 )
	background:SetPoint("BOTTOMRIGHT", Icon, "BOTTOMRIGHT", -5, 5)
   
	-- PLAYER NAME
	local name = EditBox(LootFrame, 158, 18)
	name:SetText(receiver)
	name:SetPoint("TOPLEFT",41,-1)

	-- AMOUNT EDITBOX
	local points = EditBox(LootFrame, 158, 18)
	points:SetText("-"..amount)
	points:SetPoint("TOPLEFT",41,-20)

	-- GIVE DKP BUTTON
	local button = CreateFrame("Button",nil,LootFrame)
	button:SetPoint("BOTTOMLEFT", 1,1)
	button:SetSize(200,20)
	button:SetScript("OnClick",
		function()
			if not GiveDKP(name:GetText(), points:GetText(), itemlink) then return end -- We don't wanna hide lootframe if we cant give loot because DKP_LOCK
			LootFrame:Hide()
		end)
	local label = button:CreateFontString(nil, "OVERLAY", nil)
	label:SetFont(unpack(MASTER_FONT))
	label:SetText("Give Points")
	button:SetFontString(label)
end

--
-- DKP Frame
--

local MAX_SCROLL = 0;

local BUTTONS_AMOUNT = 0;
local function GuildMemberButton()
	BUTTONS_AMOUNT = BUTTONS_AMOUNT+1

	local name = CreateFrame("Checkbutton", "GuildMembersCheckButtons"..BUTTONS_AMOUNT, GuildScrollFrameChild, "UICheckButtonTemplate")
	name:SetPoint("TOPLEFT", 0,-((BUTTONS_AMOUNT-1)*20))
	name:SetHeight(20)
	name:SetWidth(20)
	name:SetChecked(true)

	local dkp = GuildScrollFrameChild:CreateFontString(nil, "OVERLAY", nil)
	dkp:SetPoint("TOPLEFT", 100,-((BUTTONS_AMOUNT-1)*20)-5)
	dkp:SetFontObject(GameFontHighlight)
	dkp:SetHeight(20)
	name.dkp = dkp

	local remove = CreateFrame("Button", nil, name)
	remove:SetPoint("LEFT", 150,0)
	remove:SetNormalFontObject(GameFontHighlight)
	remove:SetSize(20,20)
	remove:SetText("X")
	remove:Hide()
	remove:SetScript("OnClick", function(self) RMStandby(self:GetParent().name) end)
	name.remove = remove
	
	_G["GuildScrollFrameChild"]:SetHeight(BUTTONS_AMOUNT*20)
end

local GUILD_MEMBERS_SORT = {}
local function RepaintButtons()
	if(not GUILD_MEMBERS_AMOUNT or BUTTONS_AMOUNT == 0 or not _G["DKPFrame"] or not _G["DKPFrame"]:IsShown()) then return end
      
	for i=1, GUILD_MEMBERS_AMOUNT do
		local button = _G["GuildMembersCheckButtons"..i]
		button:SetText("")
		button.dkp:SetText("")
		button.remove:Hide()
		button.name = ""
		button:Hide()
	end
	
	local online = _G["OnlineSelection"]:GetChecked()
	local raid = _G["RaidSelection"]:GetChecked()
	local standby = _G["StandbySelection"]:GetChecked()
	
	for name,member in pairs(GUILD_MEMBERS) do
		local class = _G["ClassSelection"..CLASS[member.class]]:GetChecked()
		if(class and ((online and member.online or not online) and (raid and RAID_MEMBERS[name] or not raid)) or (standby and STANDBY[name])) then
			table.insert(GUILD_MEMBERS_SORT, name)
		end
	end

	if(GUILD_MEMBERS_SORT_ORDER == "dkp") then
		table.sort(GUILD_MEMBERS_SORT, function(a,b) return GUILD_MEMBERS[a].dkp>GUILD_MEMBERS[b].dkp end)
	elseif(GUILD_MEMBERS_SORT_ORDER == "name") then
		table.sort(GUILD_MEMBERS_SORT, function(a,b) return a<b end)
	end

	for i,name in pairs(GUILD_MEMBERS_SORT) do
		local button = _G["GuildMembersCheckButtons"..i]
		_G["GuildMembersCheckButtons"..i.."Text"]:SetText(" "..name)
		button.dkp:SetText(GUILD_MEMBERS[name].dkp)
		if(STANDBY[name]) then
			button.remove:Show()
		end
		_G["GuildMembersCheckButtons"..i.."Text"]:SetTextColor(unpack(CLASS_COLORS[CLASS[GUILD_MEMBERS[name].class]]))
		button.name = name
		button:Show()
	end
	
	if(#GUILD_MEMBERS_SORT*20 < _G["GuildScrollFrame"]:GetVerticalScroll()) then _G["GuildScrollFrame"]:SetVerticalScroll(1) end
	MAX_SCROLL = (#GUILD_MEMBERS_SORT*20-228 <= 0 and 1) or #GUILD_MEMBERS_SORT*20-228
	
	for k=#GUILD_MEMBERS_SORT,1,-1 do
		GUILD_MEMBERS_SORT[k] = nil
	end

	-- RAID button (colors)
	if(UnitInRaid("player")) then
		for reward_name,amount in pairs(REWARDS) do
			_G["RewardButton"..reward_name]:Enable()
			_G["RewardButton"..reward_name.."Text"]:SetTextColor(unpack(MASTER_COLOR))
		end
		_G["RaidSelection"]:Enable()
		_G["RaidSelectionText"]:SetTextColor(unpack(MASTER_COLOR))
		_G["StandbySelection"]:Enable()
		_G["StandbySelectionText"]:SetTextColor(unpack(MASTER_COLOR))
		_G["ResetStandbyButton"]:Enable()
		_G["ResetStandbyButtonText"]:SetTextColor(unpack(MASTER_COLOR))
	else
		for reward_name,amount in pairs(REWARDS) do
			_G["RewardButton"..reward_name]:Disable()
			_G["RewardButton"..reward_name.."Text"]:SetTextColor(unpack(DISABLED_COLOR))
		end
		local raid = _G["RaidSelection"]
		raid:SetChecked(false)
		raid:Disable()
		_G["RaidSelectionText"]:SetTextColor(unpack(DISABLED_COLOR))
		local standby = _G["StandbySelection"]
		standby:SetChecked(false)
		standby:Disable()
		_G["StandbySelectionText"]:SetTextColor(unpack(DISABLED_COLOR))
		_G["ResetStandbyButton"]:Disable()
		_G["ResetStandbyButtonText"]:SetTextColor(unpack(DISABLED_COLOR))
	end
end

local function ResetStandby()
	for member,sender in pairs(STANDBY) do
		if(STANDBY[member]) then
			 SendMessage("WHISPER", "[DKP] You are not anymore in standby.", sender)
		end
	end
	for k,_ in pairs(STANDBY) do
		STANDBY[k] = nil
	end
	RepaintButtons()
end

local function RMStandby(member)
	SendMessage("WHISPER", "[DKP] You are not anymore in standby", STANDBY[member])
	STANDBY[member] = nil
	RepaintButtons()
end

local function CheckGuildButtons(value)
	for i=1, GUILD_MEMBERS_AMOUNT do
		_G["GuildMembersCheckButtons"..i]:SetChecked(value)
	end
end

-- function which is called when type /dkp
function DKP()
	if(not GUILD_MEMBERS_AMOUNT) then 
		print("[DKP] Guild roster is not loaded yet.")
		return
	end
	if _G["DKPFrame"] then
		DKPFrame:Show()
		RepaintButtons()
		return
	end

	local DKPFrame = Frame("DKPFrame","AngryDKP4",400,300)
	DKPFrame:SetPoint("CENTER", UIParent, "CENTER")
  
	local l=0;
	for class,color in pairs(CLASS_COLORS) do
		local checkbutton = CreateFrame("Checkbutton", "ClassSelection"..class, DKPFrame, "UICheckButtonTemplate")
		checkbutton:SetChecked(true)
		checkbutton:SetPoint("TOPLEFT", 5,-(l*20)-5)
		checkbutton:SetSize(20,20)
		checkbutton:SetScript("OnClick", function(self) RepaintButtons() end)
		_G[checkbutton:GetName().."Text"]:SetText(" "..class)
		_G[checkbutton:GetName().."Text"]:SetTextColor(unpack(color))
		l=l+1
	end
      
	local online = CreateFrame("Checkbutton", "OnlineSelection", DKPFrame, "UICheckButtonTemplate")
	online:SetChecked(true)
	online:SetPoint("TOPLEFT", 5,-((l+1)*20)-5)
	online:SetSize(20,20)
	online:SetScript("OnClick", RepaintButtons)
	_G["OnlineSelectionText"]:SetText("Online")
	_G["OnlineSelectionText"]:SetTextColor(unpack(MASTER_COLOR))
      
	local raid = CreateFrame("Checkbutton", "RaidSelection", DKPFrame, "UICheckButtonTemplate")
	raid:SetPoint("TOPLEFT", 5,-((l+2)*20)-5)
	raid:SetSize(20,20)
	raid:SetScript("OnClick", RepaintButtons)
	_G["RaidSelectionText"]:SetText("Raid")

	local standby = CreateFrame("Checkbutton", "StandbySelection", DKPFrame, "UICheckButtonTemplate")
	standby:SetPoint("TOPLEFT", 5,-((l+3)*20)-5)
	standby:SetSize(20,20)
	standby:SetScript("OnClick", RepaintButtons)
	_G["StandbySelectionText"]:SetText("Standby")
	
	if(not UnitInRaid("player")) then
		raid:Disable()
		standby:Disable()
	else
		raid:SetChecked(true)
	end
	
	-- Sorting template
	local f = CreateFrame("Frame", nil, DKPFrame)
	f:SetPoint("TOPLEFT", 100,-5)
	f:SetSize(190,20)
	SetTemplate(f)
	
	-- Check / Uncheck
	local check = CreateFrame("Checkbutton", nil, f, "UICheckButtonTemplate")
	check:SetChecked(true)
	check:SetPoint("TOPLEFT")
	check:SetSize(20,20)
	check:SetScript("OnClick", function(self) if(self:GetChecked()) then CheckGuildButtons(true) else CheckGuildButtons(false) end end)
	
	-- Name Sort
	local namesort = CreateFrame("Button",nil,f)
	local label = namesort:CreateFontString(nil, "OVERLAY", nil)
	label:SetFontObject(GameFontHighlight)
	label:SetText("Name")
	namesort:SetPoint("TOPLEFT", 20, 0)
	namesort:SetSize(label:GetWidth(),20)
	namesort:SetScript("OnClick",
		function(self)
			GUILD_MEMBERS_SORT_ORDER = "name"
			RepaintButtons()
		end)
	namesort:SetFontString(label)
	
	-- DKP Sort
	local dkpsort = CreateFrame("Button",nil,f)
	dkpsort:SetPoint("TOPLEFT", 100,0)
	local label = dkpsort:CreateFontString(nil, "OVERLAY", nil)
	label:SetFontObject(GameFontHighlight)
	label:SetText("DKP")
	dkpsort:SetSize(label:GetWidth(),20)
	dkpsort:SetScript("OnClick",
		function(self)
			GUILD_MEMBERS_SORT_ORDER = "dkp"
			RepaintButtons()
		end)
	dkpsort:SetFontString(label)
      
	-- Guildmembers
	local scrollframe = CreateFrame("ScrollFrame", "GuildScrollFrame", DKPFrame, nil)
	scrollframe:SetPoint("TOPLEFT",100,-27)
	scrollframe:SetSize(190,228)
	scrollframe:EnableMouseWheel(true)
	scrollframe:SetScript("OnMouseWheel", 
		function(s, delta)
			local v = s:GetVerticalScroll()-((delta < 0 and -20) or 20)
			s:SetVerticalScroll((v<=0 and 1) or (v>=MAX_SCROLL and MAX_SCROLL) or v)
		end)
	SetTemplate(scrollframe)
	
	local child = CreateFrame("Frame", "GuildScrollFrameChild", scrollframe, nil)
	child:SetWidth(170)
	scrollframe:SetScrollChild(child)

	for i=1, GUILD_MEMBERS_AMOUNT do
		GuildMemberButton() -- will set child height
	end
      
	-- REASON BOX
	local reason = EditBox(DKPFrame, 190, 18)
	reason:SetText("REASON HERE")
	reason:SetPoint("BOTTOMLEFT",100,25)
   
	-- POINTS BOX
	local points = EditBox(DKPFrame, 120, 18)
	points:SetText("+1")
	points:SetPoint("BOTTOMLEFT",100,5)
      
	-- GIVE DKP BUTTON
	local button = CreateFrame("Button","GiveDKPButton",DKPFrame)
	button:SetPoint("BOTTOMLEFT", 222,5)
	button:SetSize(68,18)
	button:SetScript("OnClick",
		function()
			CheckedDKP(points:GetText(), reason:GetText())
		end)
	local label = button:CreateFontString(nil, "OVERLAY", nil)
	label:SetFontObject(GameFontHighlight)
	label:SetText("Give DKP")
	button:SetFontString(label)
	SetTemplate(button)
      
	-- REWARD BUTTONS
	local l=0;
	for reward_name,amount in pairs(REWARDS) do
		local button = CreateFrame("Button","RewardButton"..reward_name,DKPFrame)
		button:SetPoint("TOPRIGHT", -5,-(l*21)-5)
		button:SetSize(150,20)
		button:SetScript("OnClick",
		function()
			RaidAndStanbyDKP(amount, reward_name)
		end)
		local label = button:CreateFontString("RewardButton"..reward_name.."Text", "OVERLAY", nil)
		label:SetFont(unpack(MASTER_FONT))
		label:SetText(reward_name)
		label:SetAllPoints(button)
		label:SetJustifyH("RIGHT")
		button:SetFontString(label)
		l=l+1
	end
	
	-- STANDBY RESET BUTTON
	local button = CreateFrame("Button","ResetStandbyButton",DKPFrame)
	button:SetPoint("TOPRIGHT", -5,-((l+1)*21)-5)
	button:SetSize(150,20)
	button:SetScript("OnClick",ResetStandby)
	local label = button:CreateFontString("ResetStandbyButtonText", "OVERLAY", nil)
	label:SetFont(unpack(MASTER_FONT))
	label:SetText("Reset standby")
	label:SetAllPoints(button)
	label:SetJustifyH("RIGHT")
	button:SetFontString(label)
      
	local showloots = CreateFrame("Checkbutton", "ShowLootSelection", DKPFrame, "UICheckButtonTemplate")
	showloots:SetChecked(SHOW_LOOTS)
	showloots:SetSize(20,20)
	_G["ShowLootSelectionText"]:SetText("Show loots")
	showloots:SetPoint("BOTTOMRIGHT",-5, 25)
	_G["ShowLootSelectionText"]:SetPoint("LEFT", -_G["ShowLootSelectionText"]:GetWidth(), 0)
	showloots:SetScript("OnClick",
		function(self)
			if(self:GetChecked()) then
				SHOW_LOOTS = true
			else
				SHOW_LOOTS = false
			end
		end);     

	local lootframe = CreateFrame("Checkbutton", "LootFrameSelection", DKPFrame, "UICheckButtonTemplate")
	lootframe:SetChecked(SHOW_LOOTFRAMES)
	lootframe:SetSize(20,20)
	lootframe:SetPoint("BOTTOMRIGHT",-5, 5)
	_G["LootFrameSelectionText"]:SetText("Show lootframes")
	_G["LootFrameSelectionText"]:SetPoint("LEFT", -_G["LootFrameSelectionText"]:GetWidth(), 0)
	lootframe:SetScript("OnClick",
		function(self)
			if(self:GetChecked()) then
				SHOW_LOOTFRAMES = true
			else
				SHOW_LOOTFRAMES = false
			end
		end)
      
	RepaintButtons()
end

--
-- EVENTS
--
local function OnEvent(...)
	local _,event,arg1,arg2,arg3,arg4 = ...
	if(event == "GUILD_ROSTER_UPDATE") then
		if(DKP_LOCK) then DKP_LOCK = false end
		GUILD_MEMBERS_AMOUNT = 0
		for i=1, GetNumGuildMembers(true) do
			local name,_,rankindex,level,class,_,note,_,online = GetGuildRosterInfo(i)
			if(level == MAX_LVL and ALLOWED_RANKS[rankindex]) then
				if(GUILD_MEMBERS[name]) then
					GUILD_MEMBERS[name].dkp = tonumber(note) or 0
					--GUILD_MEMBERS[name].class = CLASS[class] -- class can't change
					GUILD_MEMBERS[name].online = online
					GUILD_MEMBERS[name].index = i
				else
					GUILD_MEMBERS[name] = {["dkp"] = tonumber(note) or 0, ["online"] = online, ["class"] = CLASS[class], ["index"] = i}
				end
				GUILD_MEMBERS_AMOUNT = GUILD_MEMBERS_AMOUNT+1
			end
		end
		-- Adds more GuildMemberButtons if got new promotions or memebers
		if BUTTONS_AMOUNT < GUILD_MEMBERS_AMOUNT and not BUTTONS_AMOUNT == 0 then
			for i=1,(GUILD_MEMBERS_AMOUNT-BUTTONS_AMOUNT) do
				GuildMemberButton()
			end
		end
		RepaintButtons()
	elseif(event == "RAID_ROSTER_UPDATE") then
		for k,_ in pairs(RAID_MEMBERS) do
			RAID_MEMBERS[k] = nil
		end
		if(not UnitInRaid("player")) then
			ResetStandby() -- will call RepaintButtons()
			return
		end
		for i=1, GetNumRaidMembers() do
			local name = GetRaidRosterInfo(i)
			if(GUILD_MEMBERS[name]) then
				RAID_MEMBERS[name] = 1
				if(STANDBY[name]) then
					RMStandby(name, STANDBY[name])
				end
			end
		end
		RepaintButtons()
	elseif(event == "CHAT_MSG_ADDON" and arg1 == "AngryDKP" and arg4 ~= UnitName("player")) then
		if(arg2 == "UpdateRoster") then
			DKP_LOCK = true
			GuildRoster()
		end
	elseif(event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER") then
		if(not isML() or not GUILD_MEMBERS[arg2]) then return end
		local dkp = GUILD_MEMBERS[arg2].dkp
		if(arg1 == "allin" or arg1 == "All In" or arg1 == "all in") then
			SendMessage("RAID", "[DKP] "..arg2.." went all in. ("..dkp..")")
			BIDS[arg2] = dkp
			return
		end
		local name = string.match(arg1, "^[WwIiNn]* (.*)$")
		if(name and GUILD_MEMBERS[name] and RAID_MEMBERS[name] and name ~= arg2) then
			local winbid = GUILD_MEMBERS[name].dkp+1
			if(BIDS[name] and BIDS[name] > GUILD_MEMBERS[name].dkp-MINIUM_BID_RAISE) then -- BID is near hes max bid so and minium bid is 5
				winbid = BIDS[name]+MINIUM_BID_RAISE
			end
			if(winbid > dkp) then return; end
			SendMessage("RAID", "[DKP] "..arg2.." wins "..name.." ("..winbid..")")
			BIDS[arg2] = winbid
			return
		end
		local amount = string.match(arg1, "^[OoSsBbIiDd]* ?(%d+) ?[OoSs]*$")
		if(amount) then
			if(tonumber(amount) > dkp) then
				 SendMessage("RAID", "[DKP] "..arg2.." got only "..dkp..".")
				return
			else
				BIDS[arg2] = tonumber(amount)
			end
		end
	elseif(event == "CHAT_MSG_LOOT") then
		if(not SHOW_LOOTFRAMES or not UnitInRaid("player") or not isML()) then return end
		local receiver,itemlink = string.match(arg1, "(.+) receives? loot: (.+)%.")
		if(receiver == "You") then receiver = UnitName("player") end
		if(receiver == nil or itemlink == nil or not GUILD_MEMBERS[receiver]) then return end
		local itemname,_,itemrarity,_,_,subclass,class = GetItemInfo(itemlink)
		if(class == "Enchanting" or subclass == "Gem" or itemrarity < LOOT_RARITY or IGNORED_ITEMS[itemname]) then return end
		local amount = BIDS[receiver] or 1
		for k,v in pairs(BIDS) do
			BIDS[k] = nil
		end
		LootFrame(receiver,itemlink,amount)
	elseif(event == "CHAT_MSG_WHISPER") then
		if(not UnitInRaid("player") or not isML()) then return end
		if(arg1 == "!standby") then
			if(STANDBY[arg2]) then return end
			if(GUILD_MEMBERS[arg2]) then
				STANDBY[arg2] = arg2
				SendMessage("WHISPER", "[DKP] You are now in standby.",arg2)
				RepaintButtons()
				return
			end
		end
		local name = string.match(arg1, "!standby (.*)")
		if(name and not STANDBY[name] and GUILD_MEMBERS[name]) then
			STANDBY[name] = arg2
			SendMessage("WHISPER", "[DKP] You are now in standby",arg2)
			RepaintButtons()
		end
	elseif(event == "LOOT_OPENED") then
		if(not SHOW_LOOTS or not UnitInRaid("player") or not isML()) then return end
		if(UnitExists("target") and UnitLevel("target") ~= -1) then return end
		local target = UnitExists("target") and UnitName("target") or "Unknown"
		if(LAST_LOOTED == target and (LAST_LOOTED ~= "Unknown" and target ~= "Unknown")) then return end
		LAST_LOOTED = target
		SendMessage("RAID", target.." loot(s):")
		for i=1, GetNumLootItems() do
			if(LootSlotIsItem(i)) then
				ChatThrottleLib:SendChatMessage("NORMAL", "AngryDKP", GetLootSlotLink(i), "RAID")
			end
		end
	end
end

local frame = CreateFrame("Frame", nil, UIParent, nil)
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_RAID")
frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("LOOT_OPENED")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:SetScript("OnEVent", OnEvent)

SLASH_DKP1 = '/dkp'
SlashCmdList["DKP"] = function(query)
	if(query == "version" or query == "ver") then
		print(GetAddOnMetadata("AngryDKP4", "Notes"))
		return
	end
	DKP()
end
