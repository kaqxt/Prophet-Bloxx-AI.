-- Prophet private simulator driver for Roblox Studio.
-- Place this LocalScript beside the ProphetOfflineHarness ModuleScript and
-- ProphetStudioDashboard LocalScript in a private test place.
-- It feeds generated test states into the dashboard; it never reads live match
-- state, intercepts executor hooks, or injects player controls.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:FindFirstChild("ProphetDashboardUpdate")
if not event then
    event = Instance.new("BindableEvent")
    event.Name = "ProphetDashboardUpdate"
    event.Parent = ReplicatedStorage
end
assert(event:IsA("BindableEvent"), "ProphetDashboardUpdate must be a BindableEvent")

local moduleScript = script.Parent:FindFirstChild("prophet_offline_harness")
assert(moduleScript and moduleScript:IsA("ModuleScript"),
    "Place this LocalScript beside the prophet_offline_harness ModuleScript")

local ProphetOffline = require(moduleScript)
local bot = ProphetOffline.new()
local tick = 0
local running = true

-- Deterministic synthetic states, suitable for checking the UI and adapter.
local function makeState(t)
    local carX = math.sin(t * 0.35) * 12
    local ballX = math.sin(t * 0.22 + 1) * 28
    return {
        car_position = {x = carX, y = 0, z = -20 + t * 0.15},
        car_velocity = {x = math.cos(t * 0.35) * 8, y = 0, z = 32},
        car_forward = {x = 0, y = 0, z = 1},
        ball_position = {x = ballX, y = 2 + math.abs(math.sin(t * 0.3)) * 8, z = 18 + math.cos(t * 0.18) * 10},
        ball_velocity = {x = math.cos(t * 0.22 + 1) * 6, y = math.sin(t * 0.3) * 2, z = -2},
        opponent_goal = {x = 0, y = 0, z = 100},
        own_goal = {x = 0, y = 0, z = -100},
        boost = math.max(0, 70 - (t % 70))
    }
end

task.spawn(function()
    while running and script.Parent do
        tick += 1
        local state = makeState(tick)
        local ok, result = pcall(function()
            return bot:step(state)
        end)

        if ok and type(result) == "table" then
            result.connected = true
            result.tick = tick
            result.boost = state.boost
            result.diagnostics = result.diagnostics or {}
            result.diagnostics.tick = tick
            result.diagnostics.source = "Synthetic private-simulator state"
            result.diagnostics.physics_validated = false
            event:Fire(result)
        else
            warn("[Prophet private demo] Policy error: " .. tostring(result))
            event:Fire({
                connected = false,
                mode = "ERROR",
                tick = tick,
                diagnostics = {physics_validated = false}
            })
            break
        end

        task.wait(0.25)
    end
end)

script.Destroying:Connect(function()
    running = false
end)
