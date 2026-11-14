-- Prophet Bloxx AI dashboard UI for Roblox Studio/private simulator testing.
-- This is a visual dashboard only: it does not hook executor internals, call remotes,
-- intercept Prediction.Step/Input.Read, or automate a public live match.
--
-- Optional integration contract:
--   ReplicatedStorage.ProphetDashboardUpdate (BindableEvent)
-- Fire with a table containing:
-- {
--   connected=true/false, mode="approach", tick=12,
--   distance_to_ball=24.5, travel_time=0.4,
--   controls={throttle=1, steer=-0.2, jump=0, boost=1, handbrake=0},
--   diagnostics={heading_alignment=0.8, speed=55, boost=40, physics_validated=false}
-- }
-- In Studio, create a BindableEvent named ProphetDashboardUpdate under ReplicatedStorage.
-- If it does not exist, the UI still opens and displays waiting status.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local existing = playerGui:FindFirstChild("ProphetDashboard")
if existing then existing:Destroy() end

local function make(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local function round(parent, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, parent)
end

local function stroke(parent, color, thickness)
    make("UIStroke", {Color = color or Color3.fromRGB(62, 70, 88), Thickness = thickness or 1}, parent)
end

local gui = make("ScreenGui", {
    Name = "ProphetDashboard",
    ResetOnSpawn = false,
    IgnoreGuiInset = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, playerGui)

local root = make("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(560, 390),
    Position = UDim2.new(0.5, -280, 0.5, -195),
    BackgroundColor3 = Color3.fromRGB(17, 20, 28),
    BorderSizePixel = 0
}, gui)
round(root, 12)
stroke(root, Color3.fromRGB(66, 77, 101), 1)

local top = make("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundColor3 = Color3.fromRGB(25, 30, 42),
    BorderSizePixel = 0
}, root)
round(top, 12)
make("Frame", {
    Position = UDim2.new(0, 0, 1, -12),
    Size = UDim2.new(1, 0, 0, 12),
    BackgroundColor3 = Color3.fromRGB(25, 30, 42),
    BorderSizePixel = 0
}, top)

make("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(16, 7),
    Size = UDim2.new(1, -90, 0, 20),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "PROPHET  /  BLOXX AI",
    TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(239, 243, 255)
}, top)

make("TextLabel", {
    Position = UDim2.fromOffset(16, 27),
    Size = UDim2.new(1, -100, 0, 14),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "PRIVATE SIMULATOR DASHBOARD",
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = Color3.fromRGB(139, 153, 180)
}, top)

local close = make("TextButton", {
    Name = "Close",
    Position = UDim2.new(1, -40, 0, 9),
    Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = Color3.fromRGB(45, 51, 66),
    BorderSizePixel = 0,
    Text = "×",
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = Color3.fromRGB(235, 239, 250),
    AutoButtonColor = true
}, top)
round(close, 8)
close.Activated:Connect(function() gui:Destroy() end)

-- Drag window by its title bar.
local dragging, dragStart, startPos
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = root.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local nav = make("Frame", {
    Name = "Navigation",
    Position = UDim2.fromOffset(14, 60),
    Size = UDim2.new(0, 132, 1, -74),
    BackgroundColor3 = Color3.fromRGB(22, 26, 36),
    BorderSizePixel = 0
}, root)
round(nav, 9)

local content = make("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(158, 60),
    Size = UDim2.new(1, -172, 1, -74),
    BackgroundTransparency = 1,
    BorderSizePixel = 0
}, root)

local pages = {}
local currentPage
local function page(name)
    local frame = make("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = Color3.fromRGB(92, 110, 148),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false
    }, content)
    make("UIListLayout", {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder
    }, frame)
    make("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingBottom = UDim.new(0, 8),
        PaddingRight = UDim.new(0, 5)
    }, frame)
    pages[name] = frame
    return frame
end

local overview = page("Overview")
local controlsPage = page("Controls")
local diagnosticsPage = page("Diagnostics")

local function switch(name)
    for pageName, frame in pairs(pages) do frame.Visible = pageName == name end
    currentPage = name
    for _, child in ipairs(nav:GetChildren()) do
        if child:IsA("TextButton") then
            child.BackgroundColor3 = child.Name == name and Color3.fromRGB(59, 83, 139) or Color3.fromRGB(31, 36, 49)
            child.TextColor3 = child.Name == name and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(169, 180, 202)
        end
    end
end

local function navButton(name, label, order)
    local button = make("TextButton", {
        Name = name,
        LayoutOrder = order,
        Size = UDim2.new(1, -14, 0, 36),
        Position = UDim2.fromOffset(7, 0),
        BackgroundColor3 = Color3.fromRGB(31, 36, 49),
        BorderSizePixel = 0,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(169, 180, 202),
        AutoButtonColor = true
    }, nav)
    round(button, 7)
    button.Activated:Connect(function() switch(name) end)
end
make("UIListLayout", {Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder}, nav)
make("UIPadding", {PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7)}, nav)
navButton("Overview", "Overview", 1)
navButton("Controls", "Controls", 2)
navButton("Diagnostics", "Diagnostics", 3)

local labels = {}
local function section(parent, text)
    return make("TextLabel", {
        Size = UDim2.new(1, -2, 0, 23),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold,
        Text = text,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(235, 240, 255)
    }, parent)
end

local function card(parent, title, initial, key)
    local box = make("Frame", {
        Size = UDim2.new(1, -3, 0, 63),
        BackgroundColor3 = Color3.fromRGB(25, 30, 41),
        BorderSizePixel = 0
    }, parent)
    round(box, 8)
    make("TextLabel", {
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -24, 0, 16),
        BackgroundTransparency = 1,
        Font = Enum.Font.Gotham,
        Text = title,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(141, 155, 182)
    }, box)
    local value = make("TextLabel", {
        Position = UDim2.fromOffset(12, 27),
        Size = UDim2.new(1, -24, 0, 25),
        BackgroundTransparency = 1,
        Font = Enum.Font.GothamSemibold,
        Text = initial,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Color3.fromRGB(242, 245, 255)
    }, box)
    labels[key] = value
    return box
end

section(overview, "BOT STATUS")
card(overview, "Connection", "Waiting for simulator", "connection")
card(overview, "Current decision", "—", "mode")
card(overview, "Distance to ball", "—", "distance")
card(overview, "Estimated intercept time", "—", "travel")
local note = make("TextLabel", {
    Size = UDim2.new(1, -3, 0, 38),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    TextWrapped = true,
    Text = "Waiting for ProphetDashboardUpdate BindableEvent data.",
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextColor3 = Color3.fromRGB(139, 153, 180)
}, overview)

section(controlsPage, "NORMALIZED OUTPUTS")
card(controlsPage, "Throttle  /  0–1", "—", "throttle")
card(controlsPage, "Steer  /  -1 to 1", "—", "steer")
card(controlsPage, "Jump", "—", "jump")
card(controlsPage, "Boost", "—", "boost")
card(controlsPage, "Handbrake", "—", "handbrake")

section(diagnosticsPage, "POLICY DIAGNOSTICS")
card(diagnosticsPage, "Tick", "—", "tick")
card(diagnosticsPage, "Heading alignment", "—", "alignment")
card(diagnosticsPage, "Speed", "—", "speed")
card(diagnosticsPage, "Boost reserve", "—", "reserve")
card(diagnosticsPage, "Physics validation", "NOT VALIDATED", "physics")

local function fmt(value, decimals)
    local number = tonumber(value)
    if not number then return "—" end
    return string.format("%." .. tostring(decimals or 2) .. "f", number)
end

local function update(data)
    if type(data) ~= "table" then return end
    local controls = type(data.controls) == "table" and data.controls or {}
    local diag = type(data.diagnostics) == "table" and data.diagnostics or {}

    labels.connection.Text = data.connected == false and "Offline" or "Receiving state"
    labels.mode.Text = tostring(data.mode or "—")
    labels.distance.Text = fmt(data.distance_to_ball)
    labels.travel.Text = fmt(data.travel_time) .. " s"
    labels.throttle.Text = fmt(controls.throttle)
    labels.steer.Text = fmt(controls.steer)
    labels.jump.Text = fmt(controls.jump, 0)
    labels.boost.Text = fmt(controls.boost, 0)
    labels.handbrake.Text = fmt(controls.handbrake, 0)
    labels.tick.Text = tostring(data.tick or diag.tick or "—")
    labels.alignment.Text = fmt(diag.heading_alignment)
    labels.speed.Text = fmt(diag.speed)
    labels.reserve.Text = fmt(diag.boost or data.boost)
    labels.physics.Text = diag.physics_validated == true and "VALIDATED" or "NOT VALIDATED"
    note.Text = "Latest state received. UI displays diagnostic values only; it does not apply controls."
end

-- Wait briefly so the private demo driver can create the event even if
-- LocalScripts start in a different order.
local event = ReplicatedStorage:FindFirstChild("ProphetDashboardUpdate")
if not event then
    event = ReplicatedStorage:WaitForChild("ProphetDashboardUpdate", 10)
end

if event and event:IsA("BindableEvent") then
    event.Event:Connect(update)
else
    note.Text = "No simulator feed detected. Start ProphetPrivateDemo in a private Studio test place."
end

switch("Overview")
