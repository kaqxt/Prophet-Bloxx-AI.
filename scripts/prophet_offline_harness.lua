-- Prophet Bloxx AI: offline Lua controller harness
-- Standalone decision/control adapter for testing only.
-- No Roblox APIs, executor hooks, remotes, game input injection, or network access.
-- Coordinate convention: vectors are {x, y, z}; y is vertical.
--
-- Usage:
--   local bot = ProphetOffline.new()
--   local result = bot:step({
--     car_position={x=0,y=0,z=0},
--     car_velocity={x=0,y=0,z=30},
--     car_forward={x=0,y=0,z=1},
--     ball_position={x=25,y=0,z=15},
--     ball_velocity={x=0,y=0,z=0},
--     opponent_goal={x=0,y=0,z=100},
--     own_goal={x=0,y=0,z=-100},
--     boost=60
--   })
--   print(result.controls.throttle, result.controls.steer)

local ProphetOffline = {}

local function vec(v, name)
    assert(type(v) == "table", name .. " must be a vector table")
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    assert(x and y and z, name .. " must contain numeric x, y, z")
    assert(x == x and y == y and z == z, name .. " must be finite")
    assert(math.abs(x) < math.huge and math.abs(y) < math.huge and math.abs(z) < math.huge,
        name .. " must be finite")
    return {x=x, y=y, z=z}
end

local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function mul(a,s) return {x=a.x*s,y=a.y*s,z=a.z*s} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function length(a) return math.sqrt(dot(a,a)) end
local function norm(a)
    local n = length(a)
    if n < 1e-8 then return {x=0,y=0,z=0} end
    return mul(a,1/n)
end
local function clamp(x, lo, hi) return math.max(lo, math.min(hi,x)) end
local function ground(v) return norm({x=v.x,y=0,z=v.z}) end

function ProphetOffline.new()
    return setmetatable({}, {__index=ProphetOffline})
end

function ProphetOffline:step(input)
    assert(type(input) == "table", "state must be a table")
    local car = vec(input.car_position, "car_position")
    local velocity = vec(input.car_velocity, "car_velocity")
    local ball = vec(input.ball_position, "ball_position")
    local ballVelocity = vec(input.ball_velocity, "ball_velocity")
    local opponentGoal = vec(input.opponent_goal, "opponent_goal")
    local ownGoal = vec(input.own_goal, "own_goal")
    local forward = ground(vec(input.car_forward or {x=0,y=0,z=1}, "car_forward"))
    local boost = tonumber(input.boost or 0)
    assert(boost and boost >= 0 and boost <= 100, "boost must be between 0 and 100")

    local offset = sub(ball, car)
    local distance = length(offset)
    local speed = length(velocity)
    local travelTime = clamp(distance / math.max(speed, 24), 0.08, 1.5)

    -- Basic constant-velocity intercept estimate with provisional gravity.
    local predicted = add(ball, mul(ballVelocity, travelTime))
    predicted.y = predicted.y + 0.5 * -196.2 * travelTime * travelTime

    local goalDirection = norm(sub(opponentGoal, predicted))
    if length(goalDirection) < 1e-8 then
        goalDirection = {x=0,y=0,z=1}
    end
    local target = sub(predicted, mul(goalDirection, 5))
    local targetOffset = sub(target, car)
    local desired = norm(targetOffset)

    local alignment, steer = 1, 0
    if length(forward) > 1e-8 and length(desired) > 1e-8 then
        local cross = forward.z * desired.x - forward.x * desired.z
        local d = clamp(forward.x * desired.x + forward.z * desired.z, -1, 1)
        local angle = math.atan(cross, d)
        steer = clamp(angle / (math.pi / 2), -1, 1)
        alignment = d
    end

    local action
    if predicted.y - car.y > 7 and distance < 55 then
        action = "aerial"
    elseif distance < 9 then
        action = "challenge"
    elseif length(sub(ball, ownGoal)) < length(sub(car, ownGoal)) then
        action = "defend"
    else
        action = "approach"
    end

    local boostRecommended = distance > 45 and speed < 100 and boost > 0
    local controls = {
        throttle = alignment > -0.25 and 1 or 0.25,
        steer = steer,
        jump = action == "aerial" and 1 or 0,
        boost = boostRecommended and alignment > 0.65 and boost > 0 and 1 or 0,
        handbrake = math.abs(steer) > 0.8 and distance > 18 and 1 or 0
    }

    return {
        action = action,
        target_position = target,
        predicted_ball = predicted,
        distance_to_ball = distance,
        travel_time = travelTime,
        controls = controls,
        diagnostics = {
            heading_alignment = alignment,
            speed = speed,
            boost = boost,
            mode = action,
            physics_validated = false
        }
    }
end

-- Run lua prophet_offline_harness.lua for a small local smoke test.
if ... == nil then
    local bot = ProphetOffline.new()
    local result = bot:step({
        car_position={x=0,y=0,z=0},
        car_velocity={x=0,y=0,z=30},
        car_forward={x=0,y=0,z=1},
        ball_position={x=25,y=0,z=15},
        ball_velocity={x=0,y=0,z=0},
        opponent_goal={x=0,y=0,z=100},
        own_goal={x=0,y=0,z=-100},
        boost=60
    })
    print("Prophet offline harness — no live-game connection")
    print("mode=" .. result.action)
    print(string.format("throttle=%.2f steer=%.2f jump=%.0f boost=%.0f handbrake=%.0f",
        result.controls.throttle, result.controls.steer, result.controls.jump,
        result.controls.boost, result.controls.handbrake))
end

return ProphetOffline
