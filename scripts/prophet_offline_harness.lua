-- Prophet Bloxx AI: offline policy harness (private simulator only)
-- Decision architecture inspired by common car-soccer bot patterns:
-- prediction, kickoff, attack/challenge, shot setup, carry, defend, rotation,
-- recovery, boost budgeting, and opponent-lane avoidance.
-- This is an independent implementation for synthetic/private simulator states.
-- No Roblox APIs, executor hooks, remotes, world scans, or live input injection.
-- Vectors use plain tables {x, y, z}; y is vertical.

local ProphetOffline = {}
local DEFAULTS = {
    gravity = 196.2,
    max_prediction = 1.8,
    min_prediction = 0.08,
    dodge_cooldown = 0.62,
    kickoff_radius = 22,
    challenge_radius = 11,
    carry_radius = 28,
    defend_radius = 48,
    boost_reserve = 18,
    boost_min_distance = 45,
    dodge_min_distance = 18,
    dodge_max_distance = 115,
    aerial_height = 16,
    aerial_distance = 65,
    turn_brake_angle = 1.05,
    field_half_width = 150,
    field_half_length = 250,
    aggression = 0.72,
    rotation_discipline = 0.82,
    risk = 0.58
}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function vec(v, name, fallback)
    v = v or fallback
    assert(type(v) == "table", name .. " must be a vector table")
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    assert(finite(x) and finite(y) and finite(z), name .. " must contain finite x, y, z")
    return {x=x, y=y, z=z}
end
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function mul(a,s) return {x=a.x*s,y=a.y*s,z=a.z*s} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function len(a) return math.sqrt(dot(a,a)) end
local function flat(a) return {x=a.x,y=0,z=a.z} end
local function norm(a)
    local n=len(a)
    if n < 1e-8 then return {x=0,y=0,z=0} end
    return mul(a,1/n)
end
local function clamp(x,lo,hi) return math.max(lo,math.min(hi,x)) end
local function mix(a,b,t) return a+(b-a)*clamp(t,0,1) end

function ProphetOffline.new(config)
    local cfg = {}
    for k,v in pairs(DEFAULTS) do cfg[k]=v end
    for k,v in pairs(config or {}) do cfg[k]=v end
    return setmetatable({
        cfg=cfg, tick=0, mode="rotate", mode_time=0,
        dodge_timer=0, last_ball={x=0,y=0,z=0}, last_action="idle"
    }, {__index=ProphetOffline})
end

local function predictBall(ball, velocity, t, gravity)
    local p=add(ball,mul(velocity,t))
    p.y=math.max(0,p.y-0.5*gravity*t*t)
    return p
end

local function signedAngle(forward, target)
    local f=norm(flat(forward)); local t=norm(flat(target))
    if len(f)<1e-8 or len(t)<1e-8 then return 0, -1 end
    local cross=f.z*t.x-f.x*t.z
    local d=clamp(dot(f,t),-1,1)
    return math.atan(cross,d), d
end

local function closestOpponentThreat(car, ball, opponents)
    local lane=sub(flat(ball),flat(car))
    local laneLen=len(lane)
    if laneLen < 1 then return 0, {x=0,y=0,z=0} end
    lane=norm(lane)
    local count, avoid=0,{x=0,y=0,z=0}
    for _,op in ipairs(opponents or {}) do
        local p=vec(op.position or op.pos,"opponent.position",{x=0,y=0,z=0})
        local rel=sub(flat(p),flat(car))
        local along=dot(rel,lane)
        local lateral=len(sub(rel,mul(lane,along)))
        if along>0 and along<laneLen and lateral<12 then count=count+1 end
        local away=sub(flat(car),flat(p))
        local d=len(away)
        if d>0.01 and d<18 then
            avoid=add(avoid,mul(norm(away),(18-d)/18))
        end
    end
    return count,avoid
end

function ProphetOffline:step(input)
    assert(type(input)=="table","state must be a table")
    local car=vec(input.car_position,"car_position")
    local velocity=vec(input.car_velocity,"car_velocity")
    local ball=vec(input.ball_position,"ball_position")
    local ballVelocity=vec(input.ball_velocity,"ball_velocity")
    local ownGoal=vec(input.own_goal,"own_goal")
    local oppGoal=vec(input.opponent_goal,"opponent_goal")
    local forward=vec(input.car_forward,"car_forward",{x=0,y=0,z=1})
    local boost=clamp(tonumber(input.boost) or 0,0,100)
    local dt=clamp(tonumber(input.dt) or 1/60,0,0.05)
    local cfg=self.cfg
    self.tick=self.tick+1
    self.mode_time=self.mode_time+dt
    self.dodge_timer=math.max(0,self.dodge_timer-dt)

    local carFlat,ballFlat=flat(car),flat(ball)
    local toBall=sub(ball,car)
    local distance=len(toBall)
    local speed=len(flat(velocity))
    local closing=dot(norm(flat(velocity)),norm(sub(ballFlat,carFlat)))*speed
    local travel=clamp(distance/math.max(speed+75,100),cfg.min_prediction,cfg.max_prediction)
    -- Iteratively refine the intercept estimate so fast-moving cars lead the ball.
    local predicted=predictBall(ball,ballVelocity,travel,cfg.gravity)
    for _=1,2 do
        local interceptDistance=len(flat(sub(predicted,car)))
        travel=clamp(interceptDistance/math.max(speed+110,140),cfg.min_prediction,cfg.max_prediction)
        predicted=predictBall(ball,ballVelocity,travel,cfg.gravity)
    end

    local ownDist=len(sub(ballFlat,flat(ownGoal)))
    local oppDist=len(sub(ballFlat,flat(oppGoal)))
    local ballTowardOwn=dot(flat(ballVelocity),norm(sub(flat(ownGoal),ballFlat)))>25
    local threatCount,avoid=closestOpponentThreat(car,ball,input.opponents)

    local kickoff=(len(ballFlat)<cfg.kickoff_radius and len(flat(ballVelocity))<7)
    local defensiveUrgency=(ballTowardOwn and ownDist<cfg.defend_radius*2.2)
    local shouldRotate=(ownDist<oppDist*0.72 and distance>cfg.challenge_radius*1.4)
    local mode,target

    if kickoff then
        mode="kickoff"
        target=predicted
    elseif defensiveUrgency then
        mode="defend"
        -- Stay goal-side: move to a point between our goal and the projected ball.
        local goalToBall=norm(sub(flat(predicted),flat(ownGoal)))
        target=sub(flat(predicted),mul(goalToBall,math.min(24,ownDist*0.35)))
        target.y=math.max(0,predicted.y*0.25)
    elseif shouldRotate and cfg.rotation_discipline>0.5 then
        mode="rotation"
        local towardOwn=norm(sub(flat(ownGoal),carFlat))
        target=add(flat(ownGoal),mul(towardOwn,-18))
    elseif predicted.y>cfg.aerial_height and distance<cfg.aerial_distance and cfg.risk>0.35 then
        mode="aerial"
        target=predicted
    elseif distance<cfg.carry_radius and oppDist<ownDist and threatCount==0 and speed<125 then
        mode="carry"
        local goalDir=norm(sub(flat(oppGoal),flat(predicted)))
        target=sub(flat(predicted),mul(goalDir,7))
    elseif distance<cfg.challenge_radius then
        mode="challenge"
        target=predicted
    else
        mode="attack"
        -- Approach the ball from behind relative to the opponent goal, not straight through it.
        local goalDir=norm(sub(flat(oppGoal),flat(predicted)))
        target=sub(flat(predicted),mul(goalDir,8))
        target.y=predicted.y
    end

    -- Avoid overcommitting if another opponent occupies the direct lane.
    if threatCount>0 and mode=="attack" and distance>cfg.challenge_radius*1.4 then
        local side={x=-forward.z,y=0,z=forward.x}
        local sign=(dot(side,sub(ballFlat,carFlat))>=0) and 1 or -1
        target=add(target,mul(side,sign*math.min(12,threatCount*4)))
    end
    if len(avoid)>0.01 then target=add(target,mul(norm(avoid),8)) end

    local angle,alignment=signedAngle(forward,sub(target,car))
    local steer=clamp(angle/1.25,-1,1)
    local targetDistance=len(sub(flat(target),carFlat))
    local throttle=1
    if math.abs(angle)>cfg.turn_brake_angle then throttle=0.62 end
    if mode=="carry" then throttle=clamp(targetDistance/18,0.25,0.78) end
    if mode=="defend" or mode=="rotation" then throttle=clamp(targetDistance/30,0.35,1) end
    if alignment < -0.45 then throttle=-0.25 end

    local jump=0
    if mode=="aerial" and predicted.y>car.y+cfg.aerial_height*0.5 then jump=1 end
    local boostRecommended=distance>cfg.boost_min_distance and boost>cfg.boost_reserve
        and alignment>0.48 and mode~="carry" and mode~="defend"
    if mode=="kickoff" then boostRecommended=boost>5 and alignment>0.25 end
    if mode=="rotation" then boostRecommended=boost>cfg.boost_reserve+12 and targetDistance>35 end
    local boostControl=boostRecommended and 1 or 0

    local dodge=0
    local dodgeDistance=len(flat(sub(predicted,car)))
    if self.dodge_timer<=0 and cfg.risk>0.45 and alignment>0.88
        and speed>25 and dodgeDistance>cfg.dodge_min_distance
        and dodgeDistance<cfg.dodge_max_distance
        and (mode=="attack" or mode=="challenge" or mode=="kickoff") then
        dodge=1
        self.dodge_timer=cfg.dodge_cooldown
    end

    local handbrake=(math.abs(angle)>1.2 and distance>cfg.challenge_radius*1.5) and 1 or 0
    local result={
        action=mode,
        target_position=target,
        predicted_ball=predicted,
        distance_to_ball=distance,
        travel_time=travel,
        controls={throttle=throttle,steer=steer,jump=jump,boost=boostControl,
            handbrake=handbrake,dodge=dodge},
        diagnostics={
            tick=self.tick,heading_alignment=alignment,speed=speed,boost=boost,
            source="Prophet tactical policy (private/offline)",physics_validated=false,
            opponent_lane_threat=threatCount,closing_speed=closing,mode=mode,
            dodge_cooldown=self.dodge_timer,rotation_requested=(mode=="rotation")
        }
    }
    self.mode=mode
    self.last_action=mode
    self.last_ball=ball
    return result
end

-- Deterministic smoke test: prints a decision for a synthetic state only.
if ...==nil then
    local bot=ProphetOffline.new()
    local r=bot:step({
        car_position={x=0,y=0,z=0},car_velocity={x=0,y=0,z=30},
        car_forward={x=0,y=0,z=1},ball_position={x=25,y=0,z=15},
        ball_velocity={x=0,y=0,z=0},opponent_goal={x=0,y=0,z=100},
        own_goal={x=0,y=0,z=-100},boost=60
    })
    print("Prophet private/offline policy")
    print("mode="..r.action.." distance="..string.format("%.2f",r.distance_to_ball))
    print(string.format("throttle=%.2f steer=%.2f jump=%.0f boost=%.0f handbrake=%.0f dodge=%.0f",
        r.controls.throttle,r.controls.steer,r.controls.jump,r.controls.boost,
        r.controls.handbrake,r.controls.dodge))
end

return ProphetOffline
