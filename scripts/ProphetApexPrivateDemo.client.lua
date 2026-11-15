-- APEX x Prophet tactical-policy demo for a PRIVATE Roblox Studio place.
-- Place beside a ModuleScript named "apex_prophet_tactical_extension" and
-- ProphetVantaPrivateDashboard.client.lua. This feeds generated states to the UI.
-- It never reads live match state, scans Workspace, injects controls, or fires remotes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:FindFirstChild("ProphetDashboardUpdate")
if not event then
    event = Instance.new("BindableEvent")
    event.Name = "ProphetDashboardUpdate"
    event.Parent = ReplicatedStorage
end
assert(event:IsA("BindableEvent"), "ProphetDashboardUpdate must be a BindableEvent")

local moduleScript = script.Parent:FindFirstChild("apex_prophet_tactical_extension")
assert(moduleScript and moduleScript:IsA("ModuleScript"),
    "Place this LocalScript beside the apex_prophet_tactical_extension ModuleScript")
local dashboardAdapterScript = script.Parent:FindFirstChild("apex_prophet_dashboard_adapter")
assert(dashboardAdapterScript and dashboardAdapterScript:IsA("ModuleScript"),
    "Place this LocalScript beside the apex_prophet_dashboard_adapter ModuleScript")
local Tactics = require(moduleScript)
local DashboardAdapter = require(dashboardAdapterScript)
local bot = Tactics.new()
local tick = 0
local running = true

local function makeState(t)
    local carX = math.sin(t * 0.35) * 12
    local ballX = math.sin(t * 0.22 + 1) * 28
    local ballY = 2 + math.abs(math.sin(t * 0.3)) * 8
    local ballZ = 18 + math.cos(t * 0.18) * 10
    return {
        car_position = {x = carX, y = 2, z = -20 + t * 0.15},
        car_velocity = {x = math.cos(t * 0.35) * 8, y = 0, z = 32},
        car_forward = {x = 0, y = 0, z = 1},
        car_up = {x = 0, y = 1, z = 0},
        ball_position = {x = ballX, y = ballY, z = ballZ},
        ball_velocity = {x = math.cos(t * 0.22 + 1) * 6, y = math.sin(t * 0.3) * 2, z = -2},
        own_goal = {x = 0, y = 0, z = 220},
        opponent_goal = {x = 0, y = 0, z = -220},
        teammates = {
            {id = "blue_2", position = {x = -28, y = 2, z = 12}, velocity = {x = 0, y = 0, z = 12}}
        },
        opponents = {
            {id = "orange_1", position = {x = 24, y = 2, z = 48}, velocity = {x = -4, y = 0, z = -8}}
        },
        boost = math.max(0, 70 - (t % 70)),
        dt = 1 / 60,
        grounded = true,
        jump_available = true,
        dodge_available = true,
        score_diff = 0,
        time_left = 300
    }
end

task.spawn(function()
    while running and script.Parent do
        tick += 1
        local state = makeState(tick)
        local ok, decision = pcall(function()
            return bot:step(state)
        end)
        if ok and type(decision) == "table" then
            event:Fire(DashboardAdapter.format(decision, state, tick))
        else
            warn("[APEX x Prophet private demo] Policy error: " .. tostring(decision))
            event:Fire(DashboardAdapter.error(decision, tick))
            break
        end
        task.wait(0.25)
    end
end)

script.Destroying:Connect(function()
    running = false
end)
