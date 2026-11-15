-- Reproducible scenario factory for testing policies without a live match.
local Scenarios = {}
local function v(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
local function copy(x)
    if type(x)~="table" then return x end
    local out={}
    for k,value in pairs(x) do out[k]=copy(value) end
    return out
end
local function car(id,team,x,y,z,vx,vy,vz,yaw,boost)
    return {id=id,team=team,position=v(x,y,z),velocity=v(vx,vy,vz),
        yaw=yaw or 0,boost=boost or 50,on_ground=(z or 0)<=0}
end
local function base(name,description)
    return {name=name,description=description,ball={position=v(),velocity=v()},
        cars={},boost_pads={},metadata={tags={},expected={}}}
end
function Scenarios.kickoff()
    local s=base("kickoff","Centered ball with symmetric cars at kickoff")
    s.ball.position=v(0,0,2.1)
    s.cars={car("blue_1","blue",-28,0,0,0,0,0,0,33),
        car("orange_1","orange",28,0,0,0,0,0,math.pi,33)}
    s.metadata.tags={"kickoff","neutral","short_horizon"}
    s.metadata.expected={ball_speed_low=true,opponents_present=true}
    return s
end
function Scenarios.fast_counterattack()
    local s=base("fast_counterattack","Fast ball travelling toward the orange goal")
    s.ball.position=v(20,5,3)
    s.ball.velocity=v(82,12,2)
    s.cars={car("blue_1","blue",2,4,0,38,0,0,0,45),
        car("blue_2","blue",-10,-20,0,18,8,0,0,62),
        car("orange_1","orange",72,2,0,-20,0,0,math.pi,28)}
    s.metadata.tags={"attack","fast_ball","shot_window"}
    s.metadata.expected={positive_goal_threat=true,intercept_required=true}
    return s
end
function Scenarios.own_goal_emergency()
    local s=base("own_goal_emergency","Ball is moving rapidly toward the blue goal")
    s.ball.position=v(-72,3,4)
    s.ball.velocity=v(-48,-2,0)
    s.cars={car("blue_1","blue",-60,12,0,-8,0,0,math.pi,40),
        car("blue_2","blue",-34,-18,0,-3,0,0,math.pi,20),
        car("orange_1","orange",-28,4,0,-10,0,0,0,65)}
    s.metadata.tags={"defense","emergency","own_goal_risk"}
    s.metadata.expected={defensive_priority=true,clearance_preferred=true}
    return s
end
function Scenarios.high_aerial()
    local s=base("high_aerial","High bouncing ball with one aerial-capable car")
    s.ball.position=v(16,-8,25)
    s.ball.velocity=v(7,4,18)
    s.cars={car("blue_1","blue",3,-15,0,26,6,0,0,76),
        car("blue_2","blue",-12,18,0,14,-4,0,0,30),
        car("orange_1","orange",44,-3,0,5,0,0,math.pi,48)}
    s.metadata.tags={"aerial","high_ball","rotation"}
    s.metadata.expected={aerial_candidate=true,boost_reserve_relevant=true}
    return s
end
function Scenarios.low_boost_rotation()
    local s=base("low_boost_rotation","Low boost should discourage wasteful aerials")
    s.ball.position=v(-5,22,8)
    s.ball.velocity=v(12,-22,0)
    s.cars={car("blue_1","blue",-25,20,0,14,-4,0,0,4),
        car("blue_2","blue",5,-14,0,18,2,0,0,80),
        car("orange_1","orange",22,17,0,-8,-5,0,math.pi,52)}
    s.boost_pads={{id="small_left",position=v(-42,32,0),amount=12,active=true},
        {id="large_right",position=v(40,-32,0),amount=100,active=true}}
    s.metadata.tags={"rotation","low_boost","boost_route"}
    s.metadata.expected={boost_route_relevant=true,teammate_spacing_relevant=true}
    return s
end
function Scenarios.wall_rebound()
    local s=base("wall_rebound","Ball approaching side wall with lateral velocity")
    s.ball.position=v(10,49,9)
    s.ball.velocity=v(25,36,5)
    s.cars={car("blue_1","blue",0,28,0,22,10,0,0,55),
        car("orange_1","orange",37,22,0,8,0,0,math.pi,45)}
    s.metadata.tags={"wall","bounce_prediction","intercept"}
    s.metadata.expected={wall_bounce_expected=true}
    return s
end
function Scenarios.teammate_crowding()
    local s=base("teammate_crowding","Two teammates are close to the same challenge")
    s.ball.position=v(14,2,2.1)
    s.ball.velocity=v(-4,1,0)
    s.cars={car("blue_1","blue",0,0,0,18,0,0,0,60),
        car("blue_2","blue",2,3,0,16,0,0,0,70),
        car("orange_1","orange",30,4,0,-10,0,0,math.pi,35)}
    s.metadata.tags={"teamwork","rotation","collision_avoidance"}
    s.metadata.expected={teammate_spacing_required=true}
    return s
end
function Scenarios.empty_net()
    local s=base("empty_net","Ball is close to goal with no defender in lane")
    s.ball.position=v(73,1,3)
    s.ball.velocity=v(28,0,0)
    s.cars={car("blue_1","blue",50,-3,0,24,0,0,0,55),
        car("orange_1","orange",38,32,0,-5,0,0,math.pi,80)}
    s.metadata.tags={"shooting","open_goal","finishing"}
    s.metadata.expected={shot_candidate=true}
    return s
end
function Scenarios.scramble()
    local s=base("scramble","Low ball in contested space with four cars")
    s.ball.position=v(0,-2,2.1)
    s.ball.velocity=v(-12,7,0)
    s.cars={car("blue_1","blue",-9,-5,0,17,2,0,0,42),
        car("blue_2","blue",-22,11,0,10,-3,0,0,25),
        car("orange_1","orange",8,3,0,-13,1,0,math.pi,31),
        car("orange_2","orange",25,-15,0,-8,4,0,math.pi,58)}
    s.metadata.tags={"scramble","contested","multi_agent"}
    s.metadata.expected={multiple_threats=true}
    return s
end
function Scenarios.all()
    return {Scenarios.kickoff(),Scenarios.fast_counterattack(),Scenarios.own_goal_emergency(),
        Scenarios.high_aerial(),Scenarios.low_boost_rotation(),Scenarios.wall_rebound(),
        Scenarios.teammate_crowding(),Scenarios.empty_net(),Scenarios.scramble()}
end
function Scenarios.get(name)
    for _,scenario in ipairs(Scenarios.all()) do
        if scenario.name==name then return scenario end
    end
    return nil
end
function Scenarios.instantiate(scenario, simulator)
    assert(type(scenario)=="table","scenario must be a table")
    assert(simulator and type(simulator.set_ball)=="function","simulator is required")
    simulator:reset()
    simulator:set_ball(scenario.ball.position,scenario.ball.velocity)
    for _,c in ipairs(scenario.cars or {}) do simulator:add_car(copy(c)) end
    for _,pad in ipairs(scenario.boost_pads or {}) do simulator:add_boost_pad(copy(pad)) end
    return simulator
end
function Scenarios.validate(scenario)
    local errors={}
    if type(scenario)~="table" then return false,{"scenario must be a table"} end
    if type(scenario.name)~="string" or scenario.name=="" then errors[#errors+1]="name is required" end
    if type(scenario.ball)~="table" then errors[#errors+1]="ball state is required" end
    if type(scenario.cars)~="table" then errors[#errors+1]="cars must be a table" end
    if scenario.cars and #scenario.cars>8 then errors[#errors+1]="maximum 8 cars supported" end
    local ids={}
    for _,c in ipairs(scenario.cars or {}) do
        if not c.id then errors[#errors+1]="each car needs an id"
        elseif ids[c.id] then errors[#errors+1]="duplicate car id: "..c.id
        else ids[c.id]=true end
        if c.team~="blue" and c.team~="orange" then errors[#errors+1]="invalid team for "..tostring(c.id) end
        if not c.position then errors[#errors+1]="missing position for "..tostring(c.id) end
    end
    return #errors==0,errors
end
function Scenarios.mirror(scenario)
    local out=copy(scenario)
    local function flip(p)
        if p then p.x,p.y=-p.x,-p.y end
    end
    flip(out.ball and out.ball.position)
    if out.ball and out.ball.velocity then flip(out.ball.velocity) end
    for _,c in ipairs(out.cars or {}) do
        flip(c.position); flip(c.velocity)
        c.yaw=(c.yaw or 0)+math.pi
        c.team=c.team=="blue" and "orange" or "blue"
    end
    for _,pad in ipairs(out.boost_pads or {}) do flip(pad.position) end
    out.name=(out.name or "scenario").."_mirrored"
    return out
end
return Scenarios
