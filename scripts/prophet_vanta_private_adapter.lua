-- Prophet x Vanta-style adapter for OFFLINE / private simulator testing.
-- This preserves a Prediction.Step / Input.Read-shaped interface, but deliberately
-- does not hook Roblox internals, load remote code, or inject controls into a live game.
--
-- Expected simulator state:
-- {
--   car_position={x=...,y=...,z=...}, car_velocity={x=...,y=...,z=...},
--   car_forward={x=...,y=...,z=...}, ball_position={x=...,y=...,z=...},
--   ball_velocity={x=...,y=...,z=...}, opponent_goal={x=...,y=...,z=...},
--   own_goal={x=...,y=...,z=...}, boost=0..100
-- }
--
-- API:
--   local ProphetVanta = require("scripts.prophet_vanta_private_adapter")
--   local adapter = ProphetVanta.new()
--   local result = adapter:PredictionStep(state)
--   local controls = adapter:InputRead(state)
--
-- The simulator is responsible for providing state and consuming returned controls.

local Offline = require("scripts.prophet_offline_harness")

local ProphetVanta = {}
ProphetVanta.__index = ProphetVanta

function ProphetVanta.new()
    return setmetatable({
        bot = Offline.new(),
        last_result = nil,
        tick = 0
    }, ProphetVanta)
end

local function validate_state(state)
    assert(type(state) == "table", "state must be a table")
    local required = {
        "car_position", "car_velocity", "ball_position", "ball_velocity",
        "opponent_goal", "own_goal"
    }
    for _, key in ipairs(required) do
        assert(type(state[key]) == "table", "missing vector: " .. key)
    end
    local boost = tonumber(state.boost or 0)
    assert(boost and boost >= 0 and boost <= 100, "boost must be between 0 and 100")
end

-- Vanta-inspired prediction entry point for an offline simulator.
-- Returns the whole Prophet decision record; it does not replace engine functions.
function ProphetVanta:PredictionStep(state)
    validate_state(state)
    local result = self.bot:step(state)
    self.last_result = result
    self.tick = self.tick + 1
    result.diagnostics = result.diagnostics or {}
    result.diagnostics.tick = self.tick
    result.diagnostics.source = "Prophet offline policy"
    result.diagnostics.physics_validated = false
    return result
end

-- Vanta-inspired input-read entry point.
-- Returns normalized controls for a simulator to inspect or apply in a private test.
function ProphetVanta:InputRead(state)
    local result = self:PredictionStep(state)
    local c = result.controls
    return {
        throttle = c.throttle,
        steer = c.steer,
        jump = c.jump,
        boost = c.boost,
        handbrake = c.handbrake,
        dodge = c.dodge or 0,
        mode = result.action,
        target_position = result.target_position,
        predicted_ball = result.predicted_ball,
        tick = self.tick
    }
end

function ProphetVanta:GetDiagnostics()
    if not self.last_result then
        return {ready = false, message = "No state has been evaluated yet."}
    end
    return {
        ready = true,
        tick = self.tick,
        action = self.last_result.action,
        distance_to_ball = self.last_result.distance_to_ball,
        travel_time = self.last_result.travel_time,
        diagnostics = self.last_result.diagnostics
    }
end

return ProphetVanta
