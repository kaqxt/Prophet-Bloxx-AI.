-- Prophet-style decision layer for the private/offline Bloxx League simulator.
-- Uses general strategic ideas (prediction, shadow defense, challenge timing, boost discipline).
-- Does not copy third-party model weights or connect to a live game/executor.
-- Input vectors use {x=number,y=number,z=number}; controls are normalized.

local Policy = {}
Policy.__index = Policy

local function v(a) return {x=a.x or 0,y=a.y or 0,z=a.z or 0} end
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function mul(a,s) return {x=a.x*s,y=a.y*s,z=a.z*s} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function len(a) return math.sqrt(dot(a,a)) end
local function norm(a) local n=len(a); if n<1e-7 then return {x=0,y=0,z=0} end; return mul(a,1/n) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function flat(a) return norm({x=a.x,y=0,z=a.z}) end
local function dist(a,b) return len(sub(a,b)) end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end

function Policy.new(config)
    config = config or {}
    return setmetatable({
        gravity = config.gravity or 196.2,
        max_prediction = config.max_prediction or 1.25,
        challenge_distance = config.challenge_distance or 12,
        aerial_height = config.aerial_height or 10,
        boost_reserve = config.boost_reserve or 22,
        last_action = "approach",
        tick = 0
    }, Policy)
end

function Policy:step(s, baseBot)
    assert(type(s)=="table", "state must be a table")
    for _,k in ipairs({"car_position","car_velocity","ball_position","ball_velocity","opponent_goal","own_goal"}) do
        assert(type(s[k])=="table", "missing vector: "..k)
        for _,axis in ipairs({"x","y","z"}) do assert(finite(s[k][axis]), k.."."..axis.." must be finite") end
    end
    local car, vel, ball, bvel = v(s.car_position),v(s.car_velocity),v(s.ball_position),v(s.ball_velocity)
    local own, enemy = v(s.own_goal),v(s.opponent_goal)
    local forward = flat(v(s.car_forward or {x=0,y=0,z=1}))
    local boost = clamp(tonumber(s.boost) or 0,0,100)
    local speed = len(vel)
    local ballDist = dist(car,ball)
    local ownThreat = dist(ball,own) < dist(car,own) + 18
    local timeToBall = clamp(ballDist / math.max(speed,28),0.08,self.max_prediction)
    local predicted = add(ball,mul(bvel,timeToBall))
    predicted.y = math.max(0,predicted.y - 0.5*self.gravity*timeToBall*timeToBall)

    -- Aim behind the ball relative to the opponent goal, not straight through it.
    local shotDir = flat(sub(enemy,predicted))
    if len(shotDir)<1e-7 then shotDir={x=0,y=0,z=1} end
    local attackPoint = sub(predicted,mul(shotDir,6))
    local defendDir = flat(sub(own,predicted))
    if len(defendDir)<1e-7 then defendDir={x=0,y=0,z=-1} end
    local shadowPoint = add(predicted,mul(defendDir,13))
    local target, action

    if s.kickoff == true then
        target, action = ball, "kickoff"
    elseif ownThreat and ballDist > self.challenge_distance then
        target, action = shadowPoint, "shadow_defense"
    elseif ballDist <= self.challenge_distance then
        target, action = predicted, "challenge"
    elseif predicted.y > self.aerial_height and ballDist < 48 then
        target, action = predicted, "aerial_intercept"
    elseif ownThreat then
        target, action = shadowPoint, "defend"
    else
        target, action = attackPoint, "controlled_attack"
    end

    local desired = flat(sub(target,car))
    local alignment, steer = 1,0
    if len(forward)>1e-7 and len(desired)>1e-7 then
        local cross = forward.z*desired.x-forward.x*desired.z
        alignment = clamp(dot(forward,desired),-1,1)
        steer = clamp(math.atan(cross,alignment)/(math.pi/2),-1,1)
    end

    local targetDistance = dist(car,target)
    local throttle = alignment < -0.55 and 0.15 or 1
    local handbrake = (math.abs(steer)>0.78 and targetDistance>16 and speed>22) and 1 or 0
    local useBoost = boost>self.boost_reserve and alignment>0.78 and targetDistance>32 and speed<115
    if action=="kickoff" then useBoost = boost>0 and alignment>0.65 end
    local jump = (action=="aerial_intercept" and predicted.y-car.y>self.aerial_height) and 1 or 0

    -- When a supplied base bot is available, retain its controls only as a fallback
    -- for missing fields; the Prophet strategic layer chooses target/action.
    local baseControls = type(baseBot)=="table" and baseBot.controls or nil
    local controls = {
        throttle = finite(throttle) and throttle or (baseControls and baseControls.throttle or 0),
        steer = finite(steer) and steer or (baseControls and baseControls.steer or 0),
        jump = jump,
        boost = useBoost and 1 or 0,
        handbrake = handbrake
    }

    self.tick = self.tick + 1
    self.last_action = action
    return {
        action=action, target_position=target, predicted_ball=predicted,
        distance_to_ball=ballDist, travel_time=timeToBall, controls=controls,
        diagnostics={
            tick=self.tick, policy="Prophet-style strategic layer",
            heading_alignment=alignment, speed=speed, boost=boost,
            own_goal_threat=ownThreat, base_bot_supplied=baseControls~=nil,
            physics_validated=false
        }
    }
end

return Policy
