require "string"
require "lib/lib_Debug"
require "lib/lib_Slash"
require "lib/lib_PopupBanner"
require "lib/lib_HudScheduler"
require "lib/lib_MapMarker"
require "lib/lib_NavWheel"
require "lib/lib_InterfaceOptions"

-- ------------------------------------------
--	VARIABLES
-- ------------------------------------------
local FRAME 			= Component.GetFrame("Main")
local POPUP_FRAME		= Component.GetFrame("Popup")
local POPUP_GROUP		= Component.GetWidget("PopupContents")
local POPUP_ICON		= POPUP_GROUP:GetChild("icon")
local POPUP_TEXTS		= POPUP_GROUP:GetChild("text")
local POPUP_HEADER		= POPUP_TEXTS:GetChild("header")
local POPUP_BODY		= POPUP_TEXTS:GetChild("body")

local POPUP_WINDOW = nil
local POPUP_DUR = 3.5			-- time a popup stays on screen (must be > POPUP_CLOSE_DUR)
local POPUP_OPEN_DUR = 0.3
local POPUP_CLOSE_DUR = 0.3
local POPUP_MIN_HEIGHT = 44
local POPUP_MIN_WIDTH = 400

local ICON

local g_tornados = {}
local g_allowPopup = true
local g_popupsQueue = {}

local io_sound = "Play_UI_LevelUp_Icon_Pop"
local io_popup = true
local io_enable = false
local io_debug = false
local io_difference

--[[
	DialogScriptMessages:
	10874 - tornado
	11604 - ares
	11048 - crashed LGV
	18152 - crashed thumper
	18161 - ???
	18167 - ???
	18175 - ???
--]]

local c_TornadoDialogMessageID = 10874
local c_Tornado = 29

--[[
	[24] - Crashed Thumper
	[25] - Crashed LGV / Firefight
	[33] - Chosen Drop Pod
	[39] - ???
	[40] - ARES все
	[41] - thumper
	[42] - thumper
	[43] - thumper
	[44] - thumper
	[45] - thumper
	[46] - thumper
	[212] - Bandit Cache
	[214] - ArcStep
	[290] - OCT man
	[317] - OCT 1 Alpha
	[318] - OCT 2 Bravo
	[319] - OCT 3 Gamma
	[368] - Бронтодонт Кинг
	[399] - Giant Aranha
	[508] - Willey and others
--]]

-- ==========================================
--	Options
-- ==========================================

local function InitOptions()
	InterfaceOptions.SetCallbackFunc(OnOptionChange, "Tornado Monitor")
	InterfaceOptions.AddCheckBox({id="ENABLE", label="Enable addon", default=true})
	InterfaceOptions.AddSlider({id="DIFFERENCE", label="Level difference", tooltip="The difference in level at which tornado's markers will be shown.\nAll tornadoes will be displayed if level is exposed in 0.", default=0, min=0, max=10, inc=1})

	InterfaceOptions.StartGroup({label="Notification"})
		InterfaceOptions.AddCheckBox({id="POPUP", label="Show popup banner", tooltip="Show notification popup with tornado level.", default=true})
		InterfaceOptions.AddTextInput({id="SOUND", label="Sound notification", tooltip="ID for the sound notification.\nSounds list see on http://firefall-wiki.com/w/System_PlaySound", default="Play_UI_LevelUp_Icon_Pop"})
--		InterfaceOptions.AddChoiceMenu({id="SOUND", label="Sound notification", tooltip="ID for the sound notification.", default="Play_UI_LevelUp_Icon_Pop"})
--		InterfaceOptions.AddChoiceEntry({menuId="SOUND", val="Play_UI_LevelUp_Icon_Pop", label="Play_UI_LevelUp_Icon_Pop"})
	InterfaceOptions.StopGroup()

	InterfaceOptions.StartGroup({label="Development"})
		InterfaceOptions.AddCheckBox({id="DEBUG", label="Debug", default=false})
	InterfaceOptions.StopGroup()
end

function OnOptionChange(id, val)
	if id == "ENABLE" then
		io_enable = val

		InterfaceOptions.DisableOption("DIFFERENCE", not val)
		InterfaceOptions.DisableOption("DEBUG", not val)

		if io_difference then
			if val then
				CheckMarker()
			else
				for id,_ in pairs(g_tornados) do
					if g_tornados[id].marker then g_tornados[id]:destroy() end
				end
			end
		end
	end
	if id == "DIFFERENCE" then
		io_difference = val
		CheckMarker()
	end
	if id == "DEBUG" then
		io_debug = val
		Debug.EnableLogging(val)
	end
	if id == "SOUND" then
		io_sound = val
	end
	if id == "POPUP" then
		io_popup = val
	end
end

-- ==========================================
--	TornadoMarker Class
-- ==========================================

local tornado = {}

function tornado:new(obj)
	setmetatable(obj, { __index = tornado })

	-- create map marker
	local info = Game.GetMapMarkerInfo(obj.markerId)
	obj.marker = MapMarker.Create()

	-- set position
	obj.marker:BindToPosition({ x=info.x, y=info.y, z=info.z })

	-- set icon
	local icon = obj.marker:GetIcon()
	icon:SetIcon(info.icon_id) -- tornado icon id = 214015
	icon:SetParam("tint", info.icon_tint)
--[[ alternative set icon method
	icon:SetTexture("icons", "tornado")
	icon:SetParam("tint", "#FFFFFF")
	icon:SetParam("glow", Component.LookupColor("glow"))
	icon:SetParam("exposure", .2)
]]

	-- set title
	if io_debug then out("[Tornado Monitor]: Tornado created (id:"..tostring(obj.markerId)..", lvl:"..tostring(obj.gearStage)..")") end
	obj.marker:SetTitle(tostring(info.ToolTip).." ("..tostring(obj.gearStage)..")")

	-- additional params
	obj.marker:ShowOnHud(true)
	obj.marker:Ping()
	obj.marker:ShowTrail(true)
	obj.marker:ShowOnRadar(true)
--	obj.marker:SetIconEdge()

	-- create navwheel option
	local navDecline = NavWheel.CreateNode()
	navDecline:GetIcon():SetTexture("icons", "waypoint_cancel")
	navDecline:SetTitle(Component.LookupText("CLEAR_WAYPOINT"))
	navDecline:SetAction(function()
		NavWheel.Close()
		obj:destroy()
	end)

	-- attach option to proxy
	obj.marker:SetContextNodes({ navDecline })

	return obj
end

function tornado:update()
	local info = Game.GetMapMarkerInfo(self.markerId)
	self.marker:BindToPosition({ x=info.x, y=info.y, z=info.z })
end

function tornado:destroy()
	if io_debug then out("[Tornado Monitor]: Tornado deleted ("..tostring(self.markerId)..").") end
	self.marker:SetContextNodes(nil)
	self.marker:Destroy()
	self.marker = nil
end

-- ==========================================
--	Functions
-- ==========================================
--[[
function tm(args)
	--System.PlaySound(args[1])
	-- function for testing
	Popup_Queue(68)
	System.PlaySound("Play_UI_LevelUp_Icon_Pop")
end
]]
function out(msg)
	Debug.Log(tostring(msg))
	Component.GenerateEvent("MY_SYSTEM_MESSAGE", {text=tostring(msg)})
end

function Popup_Queue(level)
	local HUD_SLOT = HudScheduler.CreateSlot("notifications", Popup_PopNext, level)
	table.insert(g_popupsQueue, HUD_SLOT)
	HUD_SLOT:Request()
end

function Popup_PopNext(level)
	-- find a popup looking to be displayed
	local HUD_SLOT = g_popupsQueue[1]
	if (HUD_SLOT) then
		table.remove(g_popupsQueue, 1)
		Popup_Show(level)
		local dur = POPUP_DUR
		CB_Popup_Hide:Bind(Popup_Hide, HUD_SLOT)
		CB_Popup_Hide:Schedule(dur+1)
	end
end

function Popup_Hide(HUD_SLOT)
	local dur = POPUP_CLOSE_DUR
	POPUP_WINDOW:Close(dur)
	CB_FinishHidePopup:Schedule(dur)
	HUD_SLOT:Release()

	--g_ActivePopup = nil
end

function Popup_Show(level)
	if (CB_Popup_Hide:Pending()) then
		CB_Popup_Hide:Execute()
	end
	if (CB_FinishHidePopup:Pending()) then
		CB_FinishHidePopup:Execute()
	end

	POPUP_FRAME:Show(g_allowPopup)

	local color = Component.LookupColor("DynamicEvent")
	-- title
	POPUP_HEADER:SetText("Tornado")
	POPUP_HEADER:SetTextColor(color)
	local header_bounds = POPUP_HEADER:GetTextDims(false)
	local width = math.max(POPUP_MIN_WIDTH, header_bounds.width+190)	-- 100 = POPUP_TEXTS's left dim; 70 ~= PopupWindow margins
	--POPUP_WINDOW:SetColor(Component.LookupColor("DynamicEvent"))
	POPUP_WINDOW:EnableFlash(true)
	local subtitle = tostring(level).." level"
	POPUP_BODY:SetText(subtitle)

	ICON = {GROUP=Component.CreateWidget("<Group dimensions='dock:fill'/>", POPUP_ICON), WIDGET=nil}
	ICON.ART = Component.CreateWidget("<Icon dimensions='dock:fill'/>", ICON.GROUP)
	ICON.ART:SetIcon(214015)
	ICON.WIDGET = ICON.ART
	ICON.ART:SetParam("tint", color)
	
	local screen_x = Component.GetScreenSize()
	local height = header_bounds.height + POPUP_BODY:GetTextDims().height
	POPUP_HEADER:SetDims("top:_; bottom:"..(header_bounds.height - height/2).."+50%")
	POPUP_BODY:SetDims("bottom:_; top:"..(header_bounds.height - height/2).."+50%")
	--POPUP_ICON:SetDims("height:_; bottom:".. (header_bounds.height - height/2)  .."+50%")
	POPUP_ICON:SetDims("height:_; center-x:50%-8; bottom:".. (header_bounds.height - height/2)  .."+50%")
	local body_bounds = POPUP_BODY:GetTextDims(true)
	local body_height = header_bounds.height+body_bounds.height+20
	local alignment = "top:5"
	if body_height < POPUP_MIN_HEIGHT+40 then
		alignment = "center-y:50%"
	end
	POPUP_ICON:SetDims("height:_;"..alignment)
	POPUP_WINDOW:GetBody():SetDims("center-x:50%; height:"..math.max(body_height, POPUP_MIN_HEIGHT)..";width:"..math.min((math.max(body_bounds.width, header_bounds.width)*0.9)+190, screen_x*0.80))

	POPUP_TEXTS:SetDims("left:75; top:_")
	POPUP_TEXTS:SetParam("alpha", 0)

	POPUP_TEXTS:MoveTo(POPUP_TEXTS:GetInitialDims(), 0.4, 0.3, "smooth")
	POPUP_TEXTS:ParamTo("alpha", 1, 0.4, 0.3)
	POPUP_ICON:MoveTo("left:26; height:64; width:64; bottom:_", 0.6, 0.3, "smooth")

	System.PlaySound(io_sound)

	POPUP_WINDOW:Open(POPUP_OPEN_DUR)
end

function CheckInfo(args)
	local id = args.encounterId
	local myLevel = Player.GetLevel()

	if not g_tornados[id] then g_tornados[id] = {} end
	if not g_tornados[id].marker then
		if not g_tornados[id].markerId and args.markerId then
			g_tornados[id].markerId = args.markerId
		end
		if not g_tornados[id].gearStage and args.gearStage then
			g_tornados[id].gearStage = args.gearStage
		end
		-- TODO: объединить повторный код
		if io_enable and g_tornados[id].markerId and g_tornados[id].gearStage then
			local difference = math.abs(myLevel - tonumber(g_tornados[id].gearStage))
			local accept = io_difference == 0 or io_difference > 0 and (difference <= io_difference or difference == 0)
			if accept then
				g_tornados[id] = tornado:new(g_tornados[id])
				if io_popup then Popup_Queue(g_tornados[id].gearStage) end
			end
		end
	else
		if io_enable then
			local difference = math.abs(myLevel - tonumber(g_tornados[id].gearStage))
			local accept = io_difference == 0 or io_difference > 0 and (difference <= io_difference or difference == 0)
			if not accept then g_tornados[id]:destroy() end
		end
	end
end

function CheckMarker(args)
	if args and args.event == "my_encounter_added" then
		-- если нашли маркер торнадо, то создаём свой маркер с вейпоинтом
		if args.markerType == c_Tornado then
			CheckInfo({encounterId = tostring(args.encounterId), markerId = tostring(args.markerId)})
		end
	elseif args and args.event == "my_encounter_removed" then
		-- уничтожаем маркер, если удалённая миссия - торнадо
		for id,_ in pairs(g_tornados) do
			if g_tornados[id] and g_tornados[id].markerId == tostring(args.markerId) then
				if g_tornados[id].marker then g_tornados[id]:destroy() end
				for i,_ in pairs(g_tornados[id]) do g_tornados[id][i] = nil end
				g_tornados[id] = nil
				break
			end
		end
	elseif args and args.event == "on_map_marker_update" then
		-- если обновилась позиция торнадо, то обновляем наш маркер
		for id,_ in pairs(g_tornados) do
			if g_tornados[id] and g_tornados[id].markerId == tostring(args.markerId) and g_tornados[id].marker then
				g_tornados[id]:update()
				break
			end
		end
	else
		-- ищем торнадо на карте из списка
		local map_markers = Game.GetMapMarkerList()
	    for i,query in pairs(map_markers) do
			if query.markerId and query.markerType == c_Tornado then
				CheckInfo({encounterId = tostring(query.encounterId), markerId = tostring(query.markerId)})
			end
	    end
    end
end

-- ==========================================
--	Events
-- ==========================================

function OnComponentLoad()
	InitOptions()
--	LIB_SLASH.BindCallback({slash_list = "tm", description = "command for testing", func = tm})

	POPUP_WINDOW = PopupBanner.Create(POPUP_FRAME, "content")
	POPUP_WINDOW:Close(0)
	Component.FosterWidget(POPUP_GROUP, POPUP_WINDOW:GetBody())

	CB_Popup_Hide = Callback2.Create()
	CB_FinishHidePopup = Callback2.Create()
	
	CB_Popup_Hide:Bind(Popup_Hide)
	CB_FinishHidePopup:Bind(function()
		POPUP_FRAME:Show(false)

		if ICON and ICON.GROUP then
			Component.RemoveWidget(ICON.GROUP)
			ICON.GROUP = nil
			ICON.ART = nil
			ICON.SHADOW = nil
			ICON.WIDGET = nil
			ICON.FOSTER = nil
			ICON = nil
		end
	end)
end

function OnHudShow(args)
	local hide_reasons = args.requests
	local dur = args.dur or 0
	-- the rest of the frame, however, can still show up with proper excuses
	local excused_from = {"downed", "worldMap"}
	for k,reason in pairs(excused_from) do
		if (args[reason]) then
			hide_reasons = hide_reasons - 1
		end
	end
	
	if (hide_reasons <= 0) then
		FRAME:MoveTo("left:10; width:_", dur)
		FRAME:ParamTo("alpha", 1.0, dur)
	else
		FRAME:MoveTo("right:-10; width:_", dur)
		FRAME:ParamTo("alpha", 0.0, dur)
	end
	
	g_allowPopup = args.loading_screen == nil
end

function OnEncounterInfo(args)
	if args.data and args.data.gearStage and args.data.radio and (#args.data.radio > 0) then
		for i = 1, #args.data.radio do
			local str = tostring(args.data.radio[i])
			local colon = string.find(str, ":")

			if colon and (string.sub(str, 1, colon-1) == "DialogScriptMessage") then
				local dm_id = string.sub(str, colon+1)
				if dm_id == tostring(c_TornadoDialogMessageID) then
					CheckInfo({encounterId = tostring(args.encounter), gearStage = tostring(args.data.gearStage)})
				end
			end
		end
	end
end