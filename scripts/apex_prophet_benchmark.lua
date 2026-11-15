-- End-to-end offline benchmark. Simulator uses x/y floor and z-up;
-- tactical policy uses x/z floor and y-up. This file performs the explicit axis transform.
local Config=require("apex_prophet_config")
local Simulator=require("apex_prophet_simulator")
local Scenarios=require("apex_prophet_scenarios")
local Tactics=require("apex_prophet_tactical_extension")
local Evaluator=require("apex_prophet_evaluator")
local Adapter=require("apex_prophet_control_adapter")
local Benchmark={}
local function toPolicyVector(p)
    p=p or {}
    return {x=p.y or 0,y=p.z or 0,z=p.x or 0}
end
local function toPolicyState(state,carId,field)
    local selected
    for _,car in ipairs(state.cars or {}) do if car.id==carId then selected=car break end end
    assert(selected,"car id not found: "..tostring(carId))
    local forward={x=math.sin(selected.yaw or 0),y=0,z=math.cos(selected.yaw or 0)}
    local ownSign=selected.team=="blue" and -1 or 1
    local enemySign=-ownSign
    local halfLength=(field and field.half_length) or 100
    return {
        car_position=toPolicyVector(selected.position),
        car_velocity=toPolicyVector(selected.velocity),
        car_forward=forward,
        car_up={x=0,y=1,z=0},
        ball_position=toPolicyVector(state.ball.position),
        ball_velocity=toPolicyVector(state.ball.velocity),
        own_goal={x=0,y=0,z=ownSign*halfLength},
        opponent_goal={x=0,y=0,z=enemySign*halfLength},
        boost=selected.boost or 0,
        dt=1/60,
        grounded=selected.on_ground~=false,
        jump_available=(selected.jump_cooldown or 0)<=0,
        dodge_available=(selected.dodge_cooldown or 0)<=0,
        teammates=(function()
            local out={}
            for _,other in ipairs(state.cars or {}) do
                if other.team==selected.team and other.id~=selected.id then
                    out[#out+1]={position=toPolicyVector(other.position),velocity=toPolicyVector(other.velocity),id=other.id}
                end
            end
            return out
        end)(),
        opponents=(function()
            local out={}
            for _,other in ipairs(state.cars or {}) do
                if other.team~=selected.team then
                    out[#out+1]={position=toPolicyVector(other.position),velocity=toPolicyVector(other.velocity),id=other.id}
                end
            end
            return out
        end)(),
        boost_pads=(function()
            local out={}
            for _,pad in ipairs(state.boost_pads or {}) do
                if pad.active then out[#out+1]={position=toPolicyVector(pad.position),amount=pad.amount,id=pad.id} end
            end
            return out
        end)(),
        score_diff=0,time_left=300,
    }
end
local function scoreFrame(evaluator,decision,car,ball,previous)
    local d=decision.diagnostics or {}
    evaluator:observe({
        decision_ms=0,
        ball_distance=d.ball_distance or 0,
        position_error=d.ball_distance or 0,
        reward=(decision.mode=="GOAL_LINE_SAVE" and 2 or 0)
            +(decision.mode=="EMERGENCY_CLEAR" and 1.5 or 0)
            +(decision.mode=="SHOT" and 1.2 or 0)
            -(decision.mode=="BOOST_ROUTE" and 0.1 or 0),
        own_goal_risks=d.goal_threat and 1 or 0,
        action_changes=previous and (previous.mode~=decision.mode and 1 or 0) or 0,
    })
end
function Benchmark.run(options)
    options=options or {}
    local config=Config.merge(Config,options.config or {})
    local ok,errors=Config.validate(config)
    assert(ok,table.concat(errors,"; "))
    local scenarios=options.scenarios or Scenarios.all()
    local report={version=Config.version,scenario_count=#scenarios,results={},failures={}}
    local aggregate=Evaluator.new()
    for _,scenario in ipairs(scenarios) do
        local valid,problems=Scenarios.validate(scenario)
        if not valid then
            report.failures[#report.failures+1]={name=scenario.name,errors=problems}
        else
            local simulator=Simulator.new(config,options.seed or config.seed)
            Scenarios.instantiate(scenario,simulator)
            local chosen
            for _,car in ipairs(simulator.state.cars) do
                if car.team==(options.team or "blue") then chosen=car break end
            end
            if not chosen then
                report.failures[#report.failures+1]={name=scenario.name,errors={"no controlled team car"}}
            else
                local tacticsConfig=options.tactics_config or {
                    field_half_width=config.field.half_width,
                    field_half_length=config.field.half_length,
                    goal_half_width=config.field.goal_half_width,
                    goal_height=config.field.goal_height,
                    gravity=config.ball.gravity,
                    ball_radius=config.ball.radius,
                    wall_restitution=config.field.wall_restitution,
                    floor_restitution=config.field.floor_restitution,
                    car_speed_max=config.car.max_speed,
                    car_accel=config.car.acceleration,
                }
                local bot=Tactics.new(tacticsConfig)
                local adapter=Adapter.new(config)
                aggregate:start_episode({scenario=scenario.name,car_id=chosen.id})
                local previous
                local duration=options.duration or 1.2
                local ticks=math.max(1,math.floor(duration/config.fixed_dt))
                local mode_counts={}
                for _=1,ticks do
                    local policyState=toPolicyState(simulator.state,chosen.id,config.field)
                    local decision=bot:step(policyState)
                    local normalized=adapter:normalize(decision.controls,chosen.id)
                    local good,actionErrors=adapter:validate(normalized)
                    if not good then error("invalid action: "..table.concat(actionErrors,", ")) end
                    mode_counts[decision.mode]=(mode_counts[decision.mode] or 0)+1
                    scoreFrame(aggregate,decision,chosen,simulator.state.ball,previous)
                    previous=decision
                    local actions={}
                    actions[chosen.id]={steer=normalized.steer,throttle=normalized.throttle,
                        boost=normalized.boost,jump=normalized.jump,dodge=normalized.dodge}
                    simulator:step(actions,config.fixed_dt)
                end
                local episode=aggregate:finish_episode({duration=ticks*config.fixed_dt})
                report.results[#report.results+1]={name=scenario.name,car_id=chosen.id,
                    frames=ticks,modes=mode_counts,last_mode=previous.mode,
                    last_reason=previous.reason,controls=previous.controls,
                    boost_remaining=chosen.boost,episode={goal_difference=episode.goal_difference,
                    average_ball_distance=episode.average_ball_distance,
                    total_reward=episode.total_reward}}
            end
        end
    end
    report.summary=aggregate:summarize()
    report.passed=#report.results
    report.failed=#report.failures
    return report
end
function Benchmark.format(report)
    local lines={"APEX x Prophet offline benchmark","scenarios="..tostring(report.scenario_count),
        "passed="..tostring(report.passed).." failed="..tostring(report.failed)}
    for _,result in ipairs(report.results or {}) do
        lines[#lines+1]=string.format("%s | %d frames | %s | boost %.1f",
            result.name,result.frames,result.last_mode,result.boost_remaining)
    end
    for _,failure in ipairs(report.failures or {}) do
        lines[#lines+1]="FAIL "..tostring(failure.name)..": "..table.concat(failure.errors or {},", ")
    end
    return table.concat(lines,"\n")
end
return Benchmark
