-- Prophet x Vanta-style PRIVATE dashboard for Roblox Studio.
-- Visual/configuration port of the concepts in the supplied Vanta excerpt.
-- It intentionally does not use executor APIs, getgc, HttpGet/loadstring, game remotes,
-- prediction/input hooks, live match state, or player-control injection.
-- Feed: ReplicatedStorage.ProphetDashboardUpdate (BindableEvent), same schema as
-- ProphetStudioDashboard.client.lua. All settings here are local presentation/settings
-- state until a private simulator explicitly consumes them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("ProphetVantaDashboard")
if old then old:Destroy() end

local C = {
    bg = Color3.fromRGB(14, 17, 24), panel = Color3.fromRGB(22, 27, 38),
    panel2 = Color3.fromRGB(29, 35, 49), edge = Color3.fromRGB(57, 69, 91),
    text = Color3.fromRGB(239, 243, 255), muted = Color3.fromRGB(146, 160, 187),
    accent = Color3.fromRGB(87, 124, 220), good = Color3.fromRGB(86, 203, 145),
    warn = Color3.fromRGB(244, 190, 91), bad = Color3.fromRGB(239, 103, 112)
}
local settings = {
    model = "Prophet Offline Policy",
    autoFlip = false, autoRecovery = false, kickoffAssist = false,
    ballPath = true, boostESP = true, landingMarker = true,
    predictionSeconds = 2.5, pathColor = "Blue", compact = false,
    open = true
}
local latest = nil
local alive = true
local controls = {}
local labels = {}
local pages = {}
local connections = {}
local currentPage = "Main"
local content

local function make(className, props, parent)
    local obj = Instance.new(className)
    for k,v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function corner(obj, n)
    make("UICorner", {CornerRadius=UDim.new(0,n or 8)}, obj)
end
local function outline(obj, color)
    make("UIStroke", {Color=color or C.edge, Thickness=1, Transparency=0.15}, obj)
end
local function label(parent, text, size, color, height)
    return make("TextLabel", {
        BackgroundTransparency=1, Size=UDim2.new(1,0,0,height or 20),
        Font=Enum.Font.Gotham, Text=text, TextSize=size or 11,
        TextColor3=color or C.text, TextXAlignment=Enum.TextXAlignment.Left,
        TextWrapped=true
    }, parent)
end
local function fmt(v, decimals)
    local n=tonumber(v)
    if not n or n~=n or math.abs(n)==math.huge then return "—" end
    return string.format("%."..tostring(decimals or 2).."f",n)
end
local function card(parent, title, key, initial)
    local box=make("Frame",{Size=UDim2.new(1,0,0,58),BackgroundColor3=C.panel,BorderSizePixel=0},parent)
    corner(box,8)
    label(box,title,10,C.muted,16).Position=UDim2.fromOffset(11,7)
    local value=label(box,initial or "—",16,C.text,24)
    value.Position=UDim2.fromOffset(11,27)
    labels[key]=value
    return box
end
local function section(parent, title)
    local l=label(parent,title,12,C.text,22)
    l.Font=Enum.Font.GothamBold
    return l
end
local function listLayout(parent, pad)
    make("UIListLayout",{Padding=UDim.new(0,pad or 8),SortOrder=Enum.SortOrder.LayoutOrder},parent)
end
local function page(name)
    local f=make("ScrollingFrame",{
        Name=name,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,
        ScrollBarThickness=3,ScrollBarImageColor3=C.accent,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new()
    },content)
    make("UIPadding",{PaddingTop=UDim.new(0,2),PaddingRight=UDim.new(0,5),PaddingBottom=UDim.new(0,8)},f)
    listLayout(f,8)
    pages[name]=f
    return f
end
local gui=make("ScreenGui",{Name="ProphetVantaDashboard",ResetOnSpawn=false,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
local root=make("Frame",{Name="Window",Size=UDim2.fromOffset(690,480),Position=UDim2.new(.5,-345,.5,-240),BackgroundColor3=C.bg,BorderSizePixel=0},gui)
corner(root,12); outline(root)
local top=make("Frame",{Name="TitleBar",Size=UDim2.new(1,0,0,49),BackgroundColor3=C.panel,BorderSizePixel=0},root)
corner(top,12)
make("Frame",{Position=UDim2.new(0,0,1,-12),Size=UDim2.new(1,0,0,12),BackgroundColor3=C.panel,BorderSizePixel=0},top)
label(top,"PROPHET  /  VANTA PRIVATE",15,C.text,21).Position=UDim2.fromOffset(16,6)
local subtitle=label(top,"OFFLINE POLICY LAB  •  UI / VISUALS / DIAGNOSTICS",9,C.muted,14)
subtitle.Position=UDim2.fromOffset(16,28)
local close=make("TextButton",{Size=UDim2.fromOffset(30,29),Position=UDim2.new(1,-40,0,9),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="×",TextColor3=C.text,TextSize=20,Font=Enum.Font.GothamBold},top)
corner(close,7)
close.Activated:Connect(function() gui:Destroy() end)
local minimize=make("TextButton",{Size=UDim2.fromOffset(30,29),Position=UDim2.new(1,-76,0,9),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="—",TextColor3=C.text,TextSize=17,Font=Enum.Font.GothamBold},top)
corner(minimize,7)
local dragging, dragStart, startPos
top.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=input.Position; startPos=root.Position
        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)
    end
end)
table.insert(connections,UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local d=input.Position-dragStart
        root.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end))
local body=make("Frame",{Position=UDim2.fromOffset(12,58),Size=UDim2.new(1,-24,1,-70),BackgroundTransparency=1},root)
local nav=make("Frame",{Size=UDim2.new(0,145,1,0),BackgroundColor3=C.panel,BorderSizePixel=0},body)
corner(nav,9); make("UIPadding",{PaddingTop=UDim.new(0,9),PaddingLeft=UDim.new(0,8),PaddingRight=UDim.new(0,8)},nav); listLayout(nav,6)
content=make("Frame",{Position=UDim2.fromOffset(157,0),Size=UDim2.new(1,-157,1,0),BackgroundTransparency=1},body)
local function switch(name)
    currentPage=name
    for n,p in pairs(pages) do p.Visible=(n==name) end
    for _,b in ipairs(nav:GetChildren()) do
        if b:IsA("TextButton") then
            b.BackgroundColor3=b.Name==name and C.accent or C.panel2
            b.TextColor3=b.Name==name and Color3.new(1,1,1) or C.muted
        end
    end
end
local function navButton(name, order)
    local b=make("TextButton",{Name=name,LayoutOrder=order,Size=UDim2.new(1,0,0,34),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="  "..name,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamMedium,TextSize=11,TextColor3=C.muted},nav)
    corner(b,7); b.Activated:Connect(function() switch(name) end)
end
navButton("Main",1); navButton("Bot",2); navButton("Visuals",3); navButton("Settings",4); navButton("Diagnostics",5)
label(nav,"PROPHET STATUS",9,C.muted,16).LayoutOrder=20
local status=label(nav,"●  WAITING FOR FEED",10,C.warn,34); status.LayoutOrder=21
status.TextWrapped=true
label(nav,"Private Studio harness only. Returned controls are displayed, never injected.",9,C.muted,65).LayoutOrder=22

local main=page("Main")
section(main,"LIVE POLICY SNAPSHOT")
card(main,"Connection","connection","Waiting for simulator")
card(main,"Decision / mode","mode","—")
card(main,"Distance to ball","distance","—")
card(main,"Estimated intercept time","travel","—")
card(main,"Target position","target","—")
card(main,"Predicted ball position","predicted","—")
local bot=page("Bot")
section(bot,"POLICY BACKEND")
local modelText=label(bot,"Selected: "..settings.model,11,C.text,24)
local modelBtn=make("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="Switch policy source  ▾",TextColor3=C.text,Font=Enum.Font.GothamMedium,TextSize=11},bot); corner(modelBtn,7)
local modelOptions=make("Frame",{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,Visible=false},bot); listLayout(modelOptions,5)
local function modelOption(name, available)
    local b=make("TextButton",{Size=UDim2.new(1,0,0,32),BackgroundColor3=C.panel,BorderSizePixel=0,Text=name..(available and "" or "  [not connected]"),TextColor3=available and C.text or C.muted,Font=Enum.Font.Gotham,TextSize=10},modelOptions)
    corner(b,6)
    b.Activated:Connect(function()
        if not available then
            modelText.Text=name.." is not connected. No DQN checkpoint is registered."
            return
        end
        settings.model=name; modelText.Text="Selected: "..name; modelOptions.Visible=false
    end)
end
modelOption("Prophet Offline Policy",true)
modelOption("Prophet DQN Checkpoint",false)
modelBtn.Activated:Connect(function() modelOptions.Visible=not modelOptions.Visible end)
section(bot,"VANTA-STYLE ASSISTS  •  SETTINGS ONLY")
local function toggle(parent, title, key, initial)
    local row=make("Frame",{Size=UDim2.new(1,0,0,37),BackgroundColor3=C.panel,BorderSizePixel=0},parent); corner(row,7)
    label(row,title,10,C.text,32).Position=UDim2.fromOffset(11,2)
    local b=make("TextButton",{Size=UDim2.fromOffset(66,25),Position=UDim2.new(1,-76,.5,-12),BackgroundColor3=initial and C.good or C.panel2,BorderSizePixel=0,Text=initial and "ON" or "OFF",TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=10},row); corner(b,6)
    settings[key]=initial
    b.Activated:Connect(function()
        settings[key]=not settings[key]; b.Text=settings[key] and "ON" or "OFF"; b.BackgroundColor3=settings[key] and C.good or C.panel2
    end)
    return row
end
toggle(bot,"Auto flip / dodge (visual setting)","autoFlip",false)
toggle(bot,"Auto recovery / orient (visual setting)","autoRecovery",false)
toggle(bot,"Kickoff role assist (visual setting)","kickoffAssist",false)
local botNote=label(bot,"These toggles are saved in this dashboard session only. They do not drive a live character.",9,C.muted,35)

local visuals=page("Visuals")
section(visuals,"PREDICTION & ESP DISPLAY")
toggle(visuals,"Ball trajectory overlay","ballPath",true)
toggle(visuals,"Boost-pad ESP indicator","boostESP",true)
toggle(visuals,"Landing marker","landingMarker",true)
local secondsLabel=label(visuals,"Prediction horizon: "..fmt(settings.predictionSeconds,1).." seconds",11,C.text,22)
local seconds=make("Frame",{Size=UDim2.new(1,0,0,38),BackgroundColor3=C.panel,BorderSizePixel=0},visuals); corner(seconds,7)
local minus=make("TextButton",{Size=UDim2.fromOffset(34,28),Position=UDim2.fromOffset(7,5),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="−",TextColor3=C.text,TextSize=16,Font=Enum.Font.GothamBold},seconds); corner(minus,5)
local plus=make("TextButton",{Size=UDim2.fromOffset(34,28),Position=UDim2.new(1,-41,0,5),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="+",TextColor3=C.text,TextSize=16,Font=Enum.Font.GothamBold},seconds); corner(plus,5)
local secondsValue=label(seconds,fmt(settings.predictionSeconds,1).." s",11,C.text,28); secondsValue.TextXAlignment=Enum.TextXAlignment.Center; secondsValue.Position=UDim2.new(0,45,0,5); secondsValue.Size=UDim2.new(1,-90,0,28)
local function setSeconds(v) settings.predictionSeconds=math.clamp(v,0.5,5); secondsLabel.Text="Prediction horizon: "..fmt(settings.predictionSeconds,1).." seconds"; secondsValue.Text=fmt(settings.predictionSeconds,1).." s" end
minus.Activated:Connect(function() setSeconds(settings.predictionSeconds-0.5) end)
plus.Activated:Connect(function() setSeconds(settings.predictionSeconds+0.5) end)
local pathColorBtn=make("TextButton",{Size=UDim2.new(1,0,0,34),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="Path color: "..settings.pathColor.."  (click to cycle)",TextColor3=C.text,Font=Enum.Font.Gotham,TextSize=10},visuals); corner(pathColorBtn,7)
local colors={"Blue","Cyan","Purple","White"}; local colorIndex=1
pathColorBtn.Activated:Connect(function() colorIndex=colorIndex%#colors+1; settings.pathColor=colors[colorIndex]; pathColorBtn.Text="Path color: "..settings.pathColor.."  (click to cycle)" end)
local visualNote=label(visuals,"ESP and trajectory options are configuration flags for a private simulator renderer; no world scan is performed by this dashboard.",9,C.muted,42)

local settingsPage=page("Settings")
section(settingsPage,"SESSION CONFIGURATION")
local compactToggle
toggle(settingsPage,"Compact window layout","compact",false)
toggle(settingsPage,"Open dashboard at startup (session only)","open",true)
local reset=make("TextButton",{Size=UDim2.new(1,0,0,36),BackgroundColor3=C.panel2,BorderSizePixel=0,Text="Reset dashboard settings",TextColor3=C.text,Font=Enum.Font.GothamMedium,TextSize=11},settingsPage); corner(reset,7)
local settingsStatus=label(settingsPage,"Settings are in-memory only; no file writes or remote config loading.",9,C.muted,35)
reset.Activated:Connect(function()
    settings.model="Prophet Offline Policy"; settings.autoFlip=false; settings.autoRecovery=false; settings.kickoffAssist=false
    settings.ballPath=true; settings.boostESP=true; settings.landingMarker=true; settings.predictionSeconds=2.5; settings.pathColor="Blue"; settings.compact=false; settings.open=true
    settingsStatus.Text="Defaults restored in this session. Reopen dashboard to reset toggle visuals."
    modelText.Text="Selected: "..settings.model
    setSeconds(2.5)
end)

local diagnostics=page("Diagnostics")
section(diagnostics,"POLICY DIAGNOSTICS")
card(diagnostics,"Tick","tick","—")
card(diagnostics,"Heading alignment","alignment","—")
card(diagnostics,"Speed","speed","—")
card(diagnostics,"Boost reserve","reserve","—")
card(diagnostics,"Physics validation","physics","NOT VALIDATED")
card(diagnostics,"Policy source","source","—")
card(diagnostics,"Raw action","rawaction","—")
local diagNote=label(diagnostics,"No state received yet. Physics is not validated unless an independent test suite confirms it.",9,C.muted,40)

local function vectorText(v)
    if type(v)~="table" then return "—" end
    return "("..fmt(v.x,1)..", "..fmt(v.y,1)..", "..fmt(v.z,1)..")"
end
local function update(data)
    if not alive or type(data)~="table" then return end
    latest=data
    local d=type(data.diagnostics)=="table" and data.diagnostics or {}
    local c=type(data.controls)=="table" and data.controls or {}
    labels.connection.Text=data.connected==false and "Offline / error" or "Receiving simulator state"
    labels.mode.Text=tostring(data.mode or data.action or "—")
    labels.distance.Text=fmt(data.distance_to_ball)
    labels.travel.Text=fmt(data.travel_time).." s"
    labels.target.Text=vectorText(data.target_position)
    labels.predicted.Text=vectorText(data.predicted_ball)
    labels.tick.Text=tostring(data.tick or d.tick or "—")
    labels.alignment.Text=fmt(d.heading_alignment)
    labels.speed.Text=fmt(d.speed)
    labels.reserve.Text=fmt(d.boost or data.boost)
    labels.physics.Text=d.physics_validated==true and "VALIDATED" or "NOT VALIDATED"
    labels.source.Text=tostring(d.source or "—")
    labels.rawaction.Text=tostring(data.action or data.mode or "—")
    status.Text=data.connected==false and "●  OFFLINE / ERROR" or "●  FEED ACTIVE"
    status.TextColor3=data.connected==false and C.bad or C.good
    diagNote.Text="Tick "..tostring(data.tick or d.tick or "—").." • controls shown below are read-only diagnostics."
    -- Create control cards once, then update values.
    if not labels.throttle then
        card(diagnostics,"Throttle","throttle","—")
        card(diagnostics,"Steer","steer","—")
        card(diagnostics,"Jump","jump","—")
        card(diagnostics,"Boost","boost","—")
        card(diagnostics,"Handbrake","handbrake","—")
    end
    labels.throttle.Text=fmt(c.throttle); labels.steer.Text=fmt(c.steer)
    labels.jump.Text=fmt(c.jump,0); labels.boost.Text=fmt(c.boost,0); labels.handbrake.Text=fmt(c.handbrake,0)
end
minimize.Activated:Connect(function()
    settings.compact=not settings.compact
    root.Size=settings.compact and UDim2.fromOffset(690,78) or UDim2.fromOffset(690,480)
    body.Visible=not settings.compact
    minimize.Text=settings.compact and "□" or "—"
end)
local event=ReplicatedStorage:FindFirstChild("ProphetDashboardUpdate") or ReplicatedStorage:WaitForChild("ProphetDashboardUpdate",10)
if event and event:IsA("BindableEvent") then
    table.insert(connections,event.Event:Connect(update))
else
    status.Text="●  NO FEED"; status.TextColor3=C.warn
end
switch("Main")
gui.Destroying:Connect(function()
    alive=false
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
end)
