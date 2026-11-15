-- Pure data adapter from APEX decisions to the private dashboard's display schema.
-- This module has no Roblox APIs and never applies controls.
local DashboardAdapter = {}

local function number(value, fallback)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then
        return value
    end
    return fallback or 0
end

local function boolNumber(value)
    return value == true and 1 or 0
end

function DashboardAdapter.format(decision, state, tick)
    assert(type(decision) == "table", "decision must be a table")
    assert(type(state) == "table", "state must be a table")
    local diagnostics = decision.diagnostics or {}
    local controls = decision.controls or {}
    local intercept = decision.intercept or {}
    local path = decision.predicted_path or {}
    local angle = number(diagnostics.steering_angle, 0)
    local predicted = intercept.position or (path[1] and path[1].position)

    return {
        connected = true,
        tick = tick or decision.tick or 0,
        mode = decision.mode or "UNKNOWN",
        action = decision.mode or "UNKNOWN",
        target_position = decision.target,
        predicted_ball = predicted,
        distance_to_ball = number(diagnostics.ball_distance, 0),
        travel_time = number(intercept.time, 0),
        boost = number(state.boost, 0),
        controls = {
            throttle = number(controls.throttle, 0),
            steer = number(controls.steer, 0),
            jump = boolNumber(controls.jump),
            boost = boolNumber(controls.boost),
            handbrake = boolNumber(controls.handbrake),
            dodge = boolNumber(controls.dodge),
        },
        diagnostics = {
            tick = tick or decision.tick or 0,
            heading_alignment = math.cos(angle),
            speed = number(diagnostics.car_speed, 0),
            boost = number(state.boost, 0),
            source = "APEX x Prophet synthetic private state",
            physics_validated = false,
            mode = decision.mode or "UNKNOWN",
            steering_angle = angle,
        },
    }
end

function DashboardAdapter.error(message, tick)
    return {
        connected = false,
        tick = tick or 0,
        mode = "ERROR",
        action = "ERROR",
        error = tostring(message),
        diagnostics = {
            physics_validated = false,
            source = "APEX x Prophet private demo",
        },
    }
end

return DashboardAdapter
