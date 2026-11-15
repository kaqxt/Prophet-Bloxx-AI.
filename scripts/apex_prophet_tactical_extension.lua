-- APEX x PROPHET: advanced private-simulator tactical extension
-- Independent implementation. Use only with a private Studio game or offline simulator.
-- This module DOES NOT read Roblox game state, inject inputs, or control public matches.
-- Input/output vectors are plain {x=number,y=number,z=number} tables.
-- API: local Tactics = require(...); local bot = Tactics.new(config); local decision = bot:step(state)
-- Required state: car_position, car_velocity, car_forward, ball_position, ball_velocity,
-- own_goal, opponent_goal. Optional: boost (0..100), dt, teammates, opponents,
-- grounded, jump_available, dodge_available, last_touch, score_diff, time_left.

local Tactics = {}
Tactics.__index = Tactics

local DEFAULTS = {
    gravity = 196.2,
    prediction_horizon = 2.0,
    prediction_step = 0.05,
    car_speed_max = 115,
    car_accel = 38,
    car_turn_rate = 2.8,
    car_radius = 4.5,
    ball_radius = 3.5,
    goal_half_width = 40,
    goal_height = 28,
    field_half_width = 150,
    field_half_length = 250,
    wall_restitution = 0.72,
    floor_restitution = 0.62,
    kickoff_radius = 24,
    challenge_radius = 13,
    carry_radius = 30,
    defend_radius = 52,
    shadow_distance = 28,
    boost_reserve = 18,
    boost_use_speed = 72,
    boost_use_distance = 45,
    aerial_height = 15,
    aerial_distance = 62,
    aerial_min_boost = 25,
    dodge_cooldown = 0.65,
    dodge_min_distance = 18,
    dodge_max_distance = 105,
    teammate_safety_radius = 17,
    opponent_safety_radius = 13,
    shot_lane_width = 10,
    pass_lane_width = 12,
    aggression = 0.72,
    risk_tolerance = 0.55,
    rotation_discipline = 0.82,
    carry_bias = 0.35,
    wall_play_bias = 0.30,
    aerial_bias = 0.55,
    debug = false,
}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function v3(v, label, fallback)
    v = v or fallback
    assert(type(v) == "table", (label or "vector") .. " must be a table")
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    assert(finite(x) and finite(y) and finite(z), (label or "vector") .. " needs finite x/y/z")
    return {x=x, y=y, z=z}
end

local function V(x,y,z) return {x=x,y=y,z=z} end
local function add(a,b) return V(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return V(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return V(a.x*s,a.y*s,a.z*s) end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return V(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
local function len(a) return math.sqrt(dot(a,a)) end
local function flat(a) return V(a.x,0,a.z) end
local function clamp(x,a,b) return math.max(a,math.min(b,x)) end
local function mix(a,b,t) return a+(b-a)*clamp(t,0,1) end
local function norm(a)
    local m=len(a)
    if m < 1e-7 then return V(0,0,0) end
    return mul(a,1/m)
end
local function distance(a,b) return len(sub(a,b)) end
local function lerpVec(a,b,t) return add(a,mul(sub(b,a),t)) end
local function sign(x) return x < 0 and -1 or (x > 0 and 1 or 0) end
local function safeNumber(n, fallback) return finite(n) and n or fallback end

local function mergeConfig(config)
    local out = {}
    for k,v in pairs(DEFAULTS) do out[k] = v end
    for k,v in pairs(config or {}) do
        if DEFAULTS[k] ~= nil then out[k] = v end
    end
    return out
end

local function angleBetween(a,b)
    local aa, bb = norm(flat(a)), norm(flat(b))
    if len(aa) < 1e-7 or len(bb) < 1e-7 then return 0 end
    return math.acos(clamp(dot(aa,bb),-1,1))
end

local function atan2(y,x)
    -- Roblox Luau exposes math.atan2; Lua 5.3+ also supports math.atan(y, x).
    if math.atan2 then return math.atan2(y,x) end
    return math.atan(y,x)
end

local function signedAngle(a,b)
    local aa, bb = norm(flat(a)), norm(flat(b))
    if len(aa) < 1e-7 or len(bb) < 1e-7 then return 0 end
    local c = aa.z*bb.x-aa.x*bb.z
    return atan2(c, clamp(dot(aa,bb),-1,1))
end

local function predictBall(state, t, cfg)
    local p = add(state.ball_position, mul(state.ball_velocity,t))
    p.y = p.y - 0.5*cfg.gravity*t*t
    return p
end

local function predictWithBounces(state, t, cfg)
    local p = v3(state.ball_position, "ball_position")
    local velocity = v3(state.ball_velocity, "ball_velocity")
    local elapsed, step = 0, math.min(cfg.prediction_step,0.025)
    while elapsed < t do
        local dt = math.min(step,t-elapsed)
        p = add(p,mul(velocity,dt))
        velocity.y = velocity.y-cfg.gravity*dt
        if p.y < cfg.ball_radius then
            p.y = cfg.ball_radius
            if velocity.y < 0 then velocity.y = -velocity.y*cfg.floor_restitution end
        end
        if p.x > cfg.field_half_width then
            p.x = cfg.field_half_width
            velocity.x = -math.abs(velocity.x)*cfg.wall_restitution
        elseif p.x < -cfg.field_half_width then
            p.x = -cfg.field_half_width
            velocity.x = math.abs(velocity.x)*cfg.wall_restitution
        end
        if math.abs(p.z) > cfg.field_half_length then
            p.z = sign(p.z)*cfg.field_half_length
            velocity.z = -velocity.z*cfg.wall_restitution
        end
        elapsed = elapsed+dt
    end
    return p, velocity
end

local function trajectory(state,cfg)
    local points = {}
    local t = 0
    while t <= cfg.prediction_horizon+1e-6 do
        local p, vel = predictWithBounces(state,t,cfg)
        points[#points+1] = {t=t,position=p,velocity=vel}
        t=t+cfg.prediction_step
    end
    return points
end

local function findGoalCrossing(points, goal, cfg)
    local previous
    for _,sample in ipairs(points) do
        local p=sample.position
        if previous and (previous.position.z-goal.z)*(p.z-goal.z) <= 0 then
            local dz=p.z-previous.position.z
            if math.abs(dz)>1e-7 then
                local alpha=(goal.z-previous.position.z)/dz
                local crossPoint=lerpVec(previous.position,p,alpha)
                if math.abs(crossPoint.x-goal.x)<=cfg.goal_half_width
                    and crossPoint.y<=cfg.goal_height then
                    return {time=mix(previous.t,sample.t,alpha),position=crossPoint}
                end
            end
        end
        previous=sample
    end
    return nil
end

local function bestIntercept(car, velocity, points, cfg)
    local best, bestScore
    local carSpeed=len(flat(velocity))
    for _,sample in ipairs(points) do
        local target=sample.position
        local dist=distance(car,target)
        local estimatedReach=dist/math.max(22,carSpeed+cfg.car_accel*0.25)
        local lateness=math.max(0,estimatedReach-sample.t)
        local heightPenalty=math.max(0,target.y-22)*0.9
        local wallPenalty=(math.abs(target.x)>cfg.field_half_width-12 or
            math.abs(target.z)>cfg.field_half_length-12) and 5 or 0
        local score=dist+lateness*95+sample.t*7+heightPenalty+wallPenalty
        if not bestScore or score<bestScore then
            bestScore=score
            best={position=target,time=sample.t,score=score,reachable=lateness<0.18}
        end
    end
    return best or {position=points[1].position,time=0,score=0,reachable=true}
end

local function nearestEntity(car, entities)
    local best, bestDistance
    for _,entity in ipairs(entities or {}) do
        local p=v3(entity.position or entity.pos,"entity.position")
        local d=distance(car,p)
        if not bestDistance or d<bestDistance then best,bestDistance=entity,d end
    end
    return best,bestDistance
end

local function laneBlockers(from,to,entities,width)
    local line=sub(flat(to),flat(from))
    local lineLength=len(line)
    if lineLength<1e-6 then return 0,{} end
    local direction=mul(line,1/lineLength)
    local count, blockers=0,{}
    for _,entity in ipairs(entities or {}) do
        local p=v3(entity.position or entity.pos,"lane entity")
        local relative=sub(flat(p),flat(from))
        local along=dot(relative,direction)
        local lateral=len(sub(relative,mul(direction,along)))
        if along>4 and along<lineLength-4 and lateral<width then
            count=count+1
            blockers[#blockers+1]={entity=entity,along=along,lateral=lateral}
        end
    end
    return count,blockers
end

local function chooseShotTarget(ball, goal, opponents, cfg)
    local offsets={0,-0.48,0.48,-0.78,0.78}
    local best,bestScore
    for _,offset in ipairs(offsets) do
        local target=V(goal.x+offset*cfg.goal_half_width,math.min(ball.y,goal.y),goal.z)
        local blockers=laneBlockers(ball,target,opponents,cfg.shot_lane_width)
        local centrality=math.abs(offset)*0.6
        local score=blockers*12+centrality
        if not bestScore or score<bestScore then best,bestScore=target,score end
    end
    return best or goal,bestScore or 0
end

local function choosePassTarget(car, goal, teammates, opponents, cfg)
    local best,bestScore
    for _,mate in ipairs(teammates or {}) do
        local p=v3(mate.position or mate.pos,"teammate.position")
        local distanceToCar=distance(car,p)
        if distanceToCar>14 and distanceToCar<95 then
            local blockers=laneBlockers(car,p,opponents,cfg.pass_lane_width)
            local forwardProgress=distance(car,goal)-distance(p,goal)
            local score=blockers*18-distanceToCar*0.08-forwardProgress*0.15
            if not bestScore or score<bestScore then best,bestScore=p,score end
        end
    end
    return best,bestScore
end

local function nearestBoostPad(car,pads)
    local best,bestDistance
    for _,pad in ipairs(pads or {}) do
        if pad.available ~= false then
            local p=v3(pad.position or pad.pos,"boost pad")
            local d=distance(car,p)
            local value=(pad.amount or 12)/math.max(4,d)
            if not best or value>bestDistance then best,bestDistance=pad,value end
        end
    end
    return best,bestDistance
end

local function teammateHasPriority(car,ball,teammates)
    local ownDistance=distance(car,ball)
    local priority=true
    for _,mate in ipairs(teammates or {}) do
        local p=v3(mate.position or mate.pos,"teammate.position")
        if distance(p,ball)+2.5<ownDistance then priority=false end
    end
    return priority
end

local function opponentThreat(ball,ownGoal,opponents,cfg)
    local threat=0
    local nearest, nearestD
    for _,op in ipairs(opponents or {}) do
        local p=v3(op.position or op.pos,"opponent.position")
        local d=distance(p,ball)
        if not nearestD or d<nearestD then nearest,nearestD=op,d end
        local goalDistance=distance(p,ownGoal)
        if goalDistance<cfg.defend_radius and d<cfg.carry_radius then
            threat=threat+clamp((cfg.defend_radius-goalDistance)/cfg.defend_radius,0,1)
        end
    end
    return clamp(threat,0,1),nearest,nearestD
end

local function recoveryTarget(state)
    local car=state.car_position
    local forward=norm(state.car_forward)
    if len(forward)<1e-7 then forward=V(0,0,1) end
    local up=norm(state.car_up or V(0,1,0))
    if len(up)<1e-7 then up=V(0,1,0) end
    return {forward=forward,up=up,needs_recovery=dot(up,V(0,1,0))<0.45 or car.y<1.5}
end

function Tactics.new(config)
    return setmetatable({
        cfg=mergeConfig(config),
        tick=0,
        elapsed=0,
        dodge_timer=0,
        last_mode="initial",
        mode_age=0,
        last_ball=nil,
        previous_target=nil,
        history={},
    },Tactics)
end

function Tactics:reset()
    self.tick=0
    self.elapsed=0
    self.dodge_timer=0
    self.last_mode="initial"
    self.mode_age=0
    self.last_ball=nil
    self.previous_target=nil
    self.history={}
end

function Tactics:record(mode, score, state)
    self.history[#self.history+1]={tick=self.tick,mode=mode,score=score,
        ball=v3(state.ball_position,"ball_position"),time=self.elapsed}
    if #self.history>80 then table.remove(self.history,1) end
end

function Tactics:step(input)
    assert(type(input)=="table","state must be a table")
    local s={
        car_position=v3(input.car_position,"car_position"),
        car_velocity=v3(input.car_velocity,"car_velocity"),
        car_forward=v3(input.car_forward,"car_forward",V(0,0,1)),
        car_up=v3(input.car_up,"car_up",V(0,1,0)),
        ball_position=v3(input.ball_position,"ball_position"),
        ball_velocity=v3(input.ball_velocity,"ball_velocity"),
        own_goal=v3(input.own_goal,"own_goal"),
        opponent_goal=v3(input.opponent_goal,"opponent_goal"),
        teammates=input.teammates or {},
        opponents=input.opponents or {},
        boost=clamp(safeNumber(input.boost,0),0,100),
        dt=clamp(safeNumber(input.dt,1/60),0,0.05),
        grounded=input.grounded==true,
        jump_available=input.jump_available~=false,
        dodge_available=input.dodge_available~=false,
        score_diff=safeNumber(input.score_diff,0),
        time_left=safeNumber(input.time_left,math.huge),
    }
    self.tick=self.tick+1
    self.elapsed=self.elapsed+s.dt
    self.dodge_timer=math.max(0,self.dodge_timer-s.dt)
    if self.last_mode==nil then self.last_mode="initial" end

    local cfg=self.cfg
    local car,ball=s.car_position,s.ball_position
    local carToBall=sub(ball,car)
    local ballDistance=len(carToBall)
    local carSpeed=len(flat(s.car_velocity))
    local forward=norm(flat(s.car_forward))
    local target,mode,reason
    local path=trajectory(s,cfg)
    local ownCross=findGoalCrossing(path,s.own_goal,cfg)
    local enemyCross=findGoalCrossing(path,s.opponent_goal,cfg)
    local intercept=bestIntercept(car,s.car_velocity,path,cfg)
    local danger,nearestOpponent,nearestOpponentDistance=opponentThreat(ball,s.own_goal,s.opponents,cfg)
    local myPriority=teammateHasPriority(car,ball,s.teammates)
    local threatToOwnGoal=ownCross~=nil
    local inOwnHalf=distance(ball,s.own_goal)<distance(ball,s.opponent_goal)
    local shotTarget,shotScore=chooseShotTarget(ball,s.opponent_goal,s.opponents,cfg)
    local passTarget,passScore=choosePassTarget(car,s.opponent_goal,s.teammates,s.opponents,cfg)
    local blockers=laneBlockers(ball,shotTarget,s.opponents,cfg.shot_lane_width)
    local recovery=recoveryTarget(s)
    local actions={jump=false,boost=false,dodge=false,handbrake=false,air_roll=0}
    local boostPad,boostPadValue=nearestBoostPad(car,input.boost_pads)

    -- Priority 1: recover the car before any tactical commitment.
    if recovery.needs_recovery and not s.grounded then
        target=add(car,mul(recovery.forward,24))
        mode="RECOVER"
        reason="orient wheels and nose toward a stable landing"
        actions.air_roll=clamp(signedAngle(recovery.up,V(0,1,0)),-1,1)
    -- Priority 2: intercept a predicted goal crossing.
    elseif threatToOwnGoal then
        target=ownCross.position
        mode="GOAL_LINE_SAVE"
        reason="predicted ball trajectory crosses own goal"
        actions.boost=s.boost>4 and ownCross.time<0.9
        actions.jump=target.y>10 and s.jump_available
    elseif ballDistance<cfg.kickoff_radius and input.kickoff==true then
        target=ball
        mode="KICKOFF"
        reason="center-ball kickoff approach"
        actions.boost=s.boost>12
        actions.dodge=s.dodge_available and self.dodge_timer<=0 and ballDistance>cfg.dodge_min_distance
    elseif not myPriority and not inOwnHalf and cfg.rotation_discipline>0.4 then
        local goalToBall=norm(sub(ball,s.opponent_goal))
        target=add(ball,mul(goalToBall,26))
        mode="ROTATE_SUPPORT"
        reason="teammate has a better challenge angle; keep second-man spacing"
    elseif ballDistance<cfg.challenge_radius and (inOwnHalf or danger>0.35) then
        target=ball
        mode="EMERGENCY_CLEAR"
        reason="close-range defensive clear"
        actions.boost=s.boost>3
        actions.jump=ball.y>8 and s.jump_available
    elseif inOwnHalf and distance(ball,s.own_goal)<cfg.defend_radius then
        local away=norm(sub(ball,s.own_goal))
        target=add(s.own_goal,mul(away,math.min(cfg.shadow_distance,distance(ball,s.own_goal)*0.55)))
        mode="SHADOW_DEFEND"
        reason="hold a goal-side position before challenging"
    elseif ball.y>cfg.aerial_height*(1.2-0.5*clamp(cfg.aerial_bias,0,1))
        and ballDistance<cfg.aerial_distance
        and s.boost>cfg.aerial_min_boost*(1.25-0.5*clamp(cfg.risk_tolerance,0,1)) then
        target=intercept.position
        mode="AERIAL_INTERCEPT"
        reason="high ball with adequate boost and a reachable intercept"
        actions.jump=s.grounded and s.jump_available
        actions.boost=intercept.reachable
    elseif ballDistance<cfg.carry_radius and not inOwnHalf and blockers>0 and passTarget and
        (passScore or 0)<-2 and cfg.carry_bias<0.5 then
        target=passTarget
        mode="PASS"
        reason="passing lane is safer than shooting lane"
    elseif ballDistance<cfg.carry_radius and not inOwnHalf
        and carSpeed<cfg.car_speed_max*(0.78-0.2*clamp(cfg.aggression,0,1)) then
        local behind=norm(sub(s.opponent_goal,ball))
        target=sub(ball,mul(behind,8))
        mode="CARRY_SETUP"
        reason="approach behind the ball and preserve a controlled touch"
    elseif math.abs(ball.x)>cfg.field_half_width*0.72 and ballDistance<cfg.aerial_distance and
        cfg.wall_play_bias>0.25 and s.boost>cfg.aerial_min_boost then
        target=intercept.position
        mode="WALL_INTERCEPT"
        reason="wall-side trajectory offers a playable rebound"
        actions.jump=s.grounded and s.jump_available and ball.y>12
        actions.boost=intercept.reachable
    elseif ballDistance>cfg.carry_radius then
        target=intercept.position
        mode="INTERCEPT"
        reason="move to the lowest-cost reachable predicted ball point"
        actions.boost=s.boost>cfg.boost_reserve and
            (ballDistance>cfg.boost_use_distance or carSpeed<cfg.boost_use_speed)
    else
        target=shotTarget
        mode="SHOOT"
        reason="choose the least-blocked goal opening"
        actions.boost=s.boost>cfg.boost_reserve and carSpeed<cfg.car_speed_max*0.9
    end

    target=v3(target,"decision target")
    local desired=norm(flat(sub(target,car)))
    local steeringAngle=signedAngle(forward,desired)
    local turn=clamp(steeringAngle*cfg.car_turn_rate,-1,1)
    local alignment=math.cos(steeringAngle)
    local throttle=clamp(alignment, -0.35, 1)
    if math.abs(steeringAngle)>1.35 then throttle=math.min(throttle,0.15) end
    if math.abs(steeringAngle)>2.2 then actions.handbrake=true end

    -- Avoid teammate pileups by nudging the target away from nearby teammates.
    local avoidance=V(0,0,0)
    for _,mate in ipairs(s.teammates) do
        local p=v3(mate.position or mate.pos,"teammate position")
        local away=sub(flat(car),flat(p))
        local d=len(away)
        if d>0.01 and d<cfg.teammate_safety_radius then
            avoidance=add(avoidance,mul(norm(away),(cfg.teammate_safety_radius-d)/cfg.teammate_safety_radius))
        end
    end
    if len(avoidance)>0.01 and mode~="GOAL_LINE_SAVE" and mode~="EMERGENCY_CLEAR" then
        target=add(target,mul(norm(avoidance),8))
        desired=norm(flat(sub(target,car)))
        steeringAngle=signedAngle(forward,desired)
        turn=clamp(steeringAngle*cfg.car_turn_rate,-1,1)
        throttle=clamp(math.cos(steeringAngle),-0.35,1)
    end

    -- Suggest a forward dodge on a clean, ground-level intercept/shot approach.
    -- This is only a policy value; the private simulator decides whether it can execute.
    if not actions.dodge and s.grounded and s.dodge_available and self.dodge_timer<=0
        and (mode=="INTERCEPT" or mode=="SHOOT" or mode=="EMERGENCY_CLEAR")
        and ballDistance>=cfg.dodge_min_distance and ballDistance<=cfg.dodge_max_distance
        and carSpeed<cfg.car_speed_max*0.8 and math.abs(steeringAngle)<0.35 then
        actions.dodge=true
    end

    -- Dodge is a suggestion, never a direct input. Require a stable, close approach.
    if actions.dodge and (not s.grounded or self.dodge_timer>0 or ballDistance<cfg.dodge_min_distance
        or ballDistance>cfg.dodge_max_distance or math.abs(steeringAngle)>0.9) then
        actions.dodge=false
    end
    if actions.dodge then self.dodge_timer=cfg.dodge_cooldown end

    -- Boost routing is advisory and respects a reserve for saves and aerials.
    local boostReason="conserve"
    if actions.boost then boostReason="tactical acceleration" end
    if s.boost<=cfg.boost_reserve and not threatToOwnGoal then
        actions.boost=false
        boostReason="reserve protected"
    end
    if not actions.boost and boostPad and s.boost<35 and mode~="GOAL_LINE_SAVE" and mode~="EMERGENCY_CLEAR" then
        local padPos=v3(boostPad.position or boostPad.pos,"boost pad")
        if distance(car,padPos)<distance(car,ball)*0.82 then
            target=padPos
            mode="BOOST_ROUTE"
            reason="nearby available boost pad has favorable detour cost"
            desired=norm(flat(sub(target,car)))
            steeringAngle=signedAngle(forward,desired)
            turn=clamp(steeringAngle*cfg.car_turn_rate,-1,1)
            throttle=clamp(math.cos(steeringAngle),-0.35,1)
        end
    end

    local decision={
        tick=self.tick,
        mode=mode,
        reason=reason,
        target=target,
        predicted_path=path,
        intercept=intercept,
        own_goal_crossing=ownCross,
        opponent_goal_crossing=enemyCross,
        shot_target=shotTarget,
        pass_target=passTarget,
        lane_blockers=blockers,
        danger=danger,
        teammate_priority=myPriority,
        nearest_opponent=nearestOpponent,
        nearest_opponent_distance=nearestOpponentDistance,
        boost_pad=boostPad,
        boost_pad_value=boostPadValue,
        controls={throttle=throttle,steer=turn,boost=actions.boost,
            jump=actions.jump,dodge=actions.dodge,handbrake=actions.handbrake,
            air_roll=actions.air_roll},
        diagnostics={
            ball_distance=ballDistance,
            car_speed=carSpeed,
            steering_angle=steeringAngle,
            own_half=inOwnHalf,
            goal_threat=threatToOwnGoal,
            boost_reason=boostReason,
            intercept_reachable=intercept.reachable,
            shot_score=shotScore,
            time=self.elapsed,
        },
    }
    self:record(mode,intercept.score,s)
    if mode == self.last_mode then
        self.mode_age = self.mode_age + s.dt
    else
        self.last_mode = mode
        self.mode_age = 0
    end
    self.previous_target=target
    self.last_ball=ball
    return decision
end

function Tactics:getHistory()
    local out={}
    for i,item in ipairs(self.history) do
        out[i]={tick=item.tick,mode=item.mode,score=item.score,
            ball={x=item.ball.x,y=item.ball.y,z=item.ball.z},time=item.time}
    end
    return out
end

function Tactics.evaluate(scenarios,config)
    local results={}
    for index,scenario in ipairs(scenarios or {}) do
        local bot=Tactics.new(config)
        local ok,decision=pcall(function() return bot:step(scenario.state or scenario) end)
        results[#results+1]={
            name=scenario.name or ("scenario_"..index),
            ok=ok,
            mode=ok and decision.mode or "ERROR",
            reason=ok and decision.reason or tostring(decision),
            controls=ok and decision.controls or nil,
        }
    end
    return results
end

return Tactics
