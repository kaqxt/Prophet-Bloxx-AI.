-- Smoke tests for apex_prophet_tactical_extension.lua.
-- Run with a Lua 5.1+ interpreter from the repository root:
--   lua scripts/apex_prophet_smoke_test.lua
-- These tests use only synthetic plain-table states; they do not connect to Roblox.

package.path = "./scripts/?.lua;" .. package.path
local Tactics = require("apex_prophet_tactical_extension")

local function assertTrue(value, message)
    if not value then error(message or "assertion failed", 2) end
end

local function baseState()
    return {
        car_position={x=0,y=2,z=40},
        car_velocity={x=0,y=0,z=-30},
        car_forward={x=0,y=0,z=-1},
        car_up={x=0,y=1,z=0},
        ball_position={x=4,y=3,z=5},
        ball_velocity={x=0,y=0,z=-8},
        own_goal={x=0,y=0,z=220},
        opponent_goal={x=0,y=0,z=-220},
        boost=65,
        dt=1/60,
        grounded=true,
        jump_available=true,
        dodge_available=true,
        teammates={},
        opponents={},
    }
end

local function finiteNumber(n)
    return type(n)=="number" and n==n and math.abs(n)<math.huge
end

local function checkDecision(decision)
    assertTrue(type(decision)=="table","decision must be a table")
    assertTrue(type(decision.mode)=="string","mode must be a string")
    assertTrue(type(decision.reason)=="string","reason must be a string")
    assertTrue(type(decision.target)=="table","target must exist")
    for _,axis in ipairs({"x","y","z"}) do
        assertTrue(finiteNumber(decision.target[axis]),"target axis "..axis.." must be finite")
    end
    for _,key in ipairs({"throttle","steer"}) do
        assertTrue(finiteNumber(decision.controls[key]),key.." must be finite")
    end
    assertTrue(decision.controls.throttle>=-1 and decision.controls.throttle<=1,"throttle range")
    assertTrue(decision.controls.steer>=-1 and decision.controls.steer<=1,"steer range")
    assertTrue(type(decision.predicted_path)=="table","trajectory must be returned")
end

local function testBaseline()
    local bot=Tactics.new()
    local d=bot:step(baseState())
    checkDecision(d)
    assertTrue(#d.predicted_path>2,"trajectory should have multiple samples")
end

local function testGoalThreat()
    local s=baseState()
    s.ball_position={x=0,y=4,z=180}
    s.ball_velocity={x=0,y=0,z=70}
    s.own_goal={x=0,y=0,z=220}
    s.opponent_goal={x=0,y=0,z=-220}
    local d=Tactics.new():step(s)
    checkDecision(d)
    assertTrue(d.own_goal_crossing~=nil,"trajectory should detect own-goal crossing")
    assertTrue(d.mode=="GOAL_LINE_SAVE","goal threat should prioritize save")
end

local function testHighBall()
    local s=baseState()
    s.ball_position={x=10,y=35,z=0}
    s.ball_velocity={x=0,y=2,z=-5}
    s.car_position={x=0,y=2,z=20}
    s.boost=90
    local d=Tactics.new():step(s)
    checkDecision(d)
    assertTrue(d.mode=="AERIAL_INTERCEPT" or d.mode=="INTERCEPT" or d.mode=="RECOVER",
        "high-ball state should produce an aerial/intercept/recovery decision")
end

local function testTeammateRotation()
    local s=baseState()
    s.car_position={x=0,y=2,z=60}
    s.ball_position={x=0,y=3,z=0}
    s.teammates={{position={x=1,y=2,z=4}}}
    s.own_goal={x=0,y=0,z=220}
    s.opponent_goal={x=0,y=0,z=-220}
    local d=Tactics.new():step(s)
    checkDecision(d)
    assertTrue(d.mode=="ROTATE_SUPPORT" or d.mode=="INTERCEPT" or d.mode=="SHOOT"
        or d.mode=="CARRY_SETUP" or d.mode=="SHADOW_DEFEND",
        "team scenario should select a valid tactical mode")
end

local function testLowBoostReserve()
    local s=baseState()
    s.boost=5
    s.ball_position={x=40,y=3,z=-100}
    local d=Tactics.new():step(s)
    checkDecision(d)
    assertTrue(d.controls.boost==false or d.mode=="GOAL_LINE_SAVE" or d.mode=="EMERGENCY_CLEAR",
        "low boost should be conserved outside emergencies")
end

local function testRepeatability()
    local s=baseState()
    local a=Tactics.new():step(s)
    local b=Tactics.new():step(s)
    assertTrue(a.mode==b.mode,"same synthetic state should choose same mode")
    assertTrue(math.abs(a.target.x-b.target.x)<1e-7,"same state should choose same target")
end

local tests={
    {"baseline",testBaseline},
    {"goal threat",testGoalThreat},
    {"high ball",testHighBall},
    {"teammate rotation",testTeammateRotation},
    {"low boost reserve",testLowBoostReserve},
    {"repeatability",testRepeatability},
}

local passed=0
for _,test in ipairs(tests) do
    local ok,err=pcall(test[2])
    if not ok then
        io.stderr:write("FAIL: ",test[1],": ",tostring(err),"\n")
        os.exit(1)
    end
    passed=passed+1
    io.write("PASS: ",test[1],"\n")
end
io.write("All ",passed," synthetic smoke tests passed.\n")
