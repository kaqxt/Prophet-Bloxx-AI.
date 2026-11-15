-- Small deterministic hyperparameter sweep for synthetic offline scenarios.
-- This optimizes a synthetic proxy score, not real match win rate.
local Config=require("apex_prophet_config")
local Scenarios=require("apex_prophet_scenarios")
local Benchmark=require("apex_prophet_benchmark")
local Tuner={}
local function copy(v)
    if type(v)~="table" then return v end
    local out={}
    for k,x in pairs(v) do out[k]=copy(x) end
    return out
end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function setPath(root,path,value)
    local keys={}
    for key in string.gmatch(path,"[^%.]+") do keys[#keys+1]=key end
    assert(#keys>0,"path cannot be empty")
    local node=root
    for i=1,#keys-1 do
        assert(type(node[keys[i]])=="table","invalid config path: "..path)
        node=node[keys[i]]
    end
    assert(node[keys[#keys]]~=nil,"unknown config field: "..path)
    node[keys[#keys]]=value
end
local function scoreReport(report,weights)
    weights=weights or {}
    local summary=report.summary or {}
    local score=0
    score=score+(summary.total_reward or 0)*(weights.reward or 1)
    score=score+(summary.goal_difference or 0)*(weights.goal_difference or 2)
    score=score-(summary.mean_position_error or 0)*(weights.position_error or 0.025)
    score=score-(summary.own_goal_risks or 0)*(weights.own_goal_risk or 4)
    score=score-(summary.mean_stale_action_rate or 0)*(weights.stale_actions or 5)
    score=score-(report.failed or 0)*(weights.failed_scenarios or 100)
    return score
end
local function normalizeCandidate(base,patch)
    local candidate=copy(base)
    for path,value in pairs(patch or {}) do setPath(candidate,path,value) end
    return candidate
end
function Tuner.default_candidates()
    return {
        {name="balanced",patch={}},
        {name="aggressive",patch={["tactics.aggression"]=0.86,["tactics.carry_bias"]=0.24}},
        {name="defensive",patch={["tactics.rotation_discipline"]=0.96,["tactics.risk_tolerance"]=0.35}},
        {name="aerial_conservative",patch={["tactics.aerial_bias"]=0.3,["tactics.boost_reserve"]=28}},
        {name="aerial_aggressive",patch={["tactics.aerial_bias"]=0.78,["tactics.boost_reserve"]=15}},
        {name="carry_focused",patch={["tactics.carry_bias"]=0.65,["tactics.aggression"]=0.62}},
        {name="fast_intercepts",patch={["tactics.prediction_horizon"]=2.4,["tactics.prediction_step"]=0.04}},
        {name="rotation_focused",patch={["tactics.rotation_discipline"]=0.98,["tactics.teammate_safety_radius"]=22}},
    }
end
function Tuner.expand(base,candidates)
    local expanded={}
    for _,candidate in ipairs(candidates or {}) do
        local config=copy(base or {})
        local tactics=copy(candidate.tactics or {})
        local sim=copy(candidate.simulator or {})
        for path,value in pairs(candidate.patch or {}) do
            local section,field=string.match(path,"^([^%.]+)%.(.+)$")
            if section=="tactics" then tactics[field]=value
            elseif section=="simulator" then
                sim[field]=value
            elseif section=="policy" then
                if type(config.policy)~="table" then config.policy={} end
                config.policy[field]=value
            else
                error("unsupported candidate patch path: "..tostring(path))
            end
        end
        expanded[#expanded+1]={name=candidate.name or ("candidate_"..#expanded+1),
            config=config,tactics=tactics,simulator=sim}
    end
    return expanded
end
function Tuner.run(options)
    options=options or {}
    local base=options.config or Config
    local candidates=options.candidates or Tuner.default_candidates()
    local valid,problems=Tuner.validate_candidates(candidates)
    assert(valid,table.concat(problems,"; "))
    local expanded=Tuner.expand(base,candidates)
    local scenarios=options.scenarios or Scenarios.all()
    local max_trials=math.max(1,math.min(options.max_trials or #expanded,100))
    local results={}
    for index,candidate in ipairs(expanded) do
        if index>max_trials then break end
        local simConfig=Config.merge(base,candidate.config or {})
        simConfig=Config.merge(simConfig,candidate.simulator or {})
        local report=Benchmark.run({
            config=simConfig,
            scenarios=scenarios,
            duration=options.duration or 0.4,
            seed=(options.seed or Config.seed)+index,
            tactics_config=candidate.tactics,
            team=options.team or "blue",
        })
        results[#results+1]={name=candidate.name or ("candidate_"..index),
            score=scoreReport(report,options.weights),report=report,
            tactics=copy(candidate.tactics or {}),simulator=copy(candidate.simulator or {})}
    end
    table.sort(results,function(a,b)
        if a.score==b.score then return a.name<b.name end
        return a.score>b.score
    end)
    return {method="synthetic_proxy_sweep",tested=#results,results=results,
        best=results[1],warning="Scores use synthetic scenarios and proxy rewards; they do not predict real-game win rate."}
end
function Tuner.format(result)
    local lines={"APEX x Prophet synthetic tuning report",
        "method="..tostring(result.method),
        "tested="..tostring(result.tested),
        tostring(result.warning or "")}
    for rank,item in ipairs(result.results or {}) do
        lines[#lines+1]=string.format("%d. %s score=%.3f pass=%d fail=%d",
            rank,item.name,item.score,item.report.passed or 0,item.report.failed or 0)
    end
    if result.best then lines[#lines+1]="best_candidate="..result.best.name end
    return table.concat(lines,"\n")
end
function Tuner.validate_candidates(candidates)
    local errors={}
    if type(candidates)~="table" then return false,{"candidates must be a table"} end
    if #candidates==0 then errors[#errors+1]="at least one candidate is required" end
    if #candidates>100 then errors[#errors+1]="maximum 100 candidates per run" end
    local names={}
    for i,candidate in ipairs(candidates) do
        if type(candidate)~="table" then errors[#errors+1]="candidate "..i.." must be a table"
        else
            local name=candidate.name or ("candidate_"..i)
            if names[name] then errors[#errors+1]="duplicate candidate name: "..name end
            names[name]=true
            if candidate.patch~=nil and type(candidate.patch)~="table" then
                errors[#errors+1]=name.." patch must be a table"
            end
        end
    end
    return #errors==0,errors
end
function Tuner.grid(parameter,values,base)
    assert(type(parameter)=="string" and parameter~="","parameter path required")
    assert(type(values)=="table","values must be a table")
    local out={}
    for i,value in ipairs(values) do
        out[#out+1]={name=parameter.."_"..tostring(value),patch={[parameter]=value},base=copy(base or {})}
    end
    return out
end
function Tuner.suggest_next(best,parameter,low,high,count)
    count=math.max(2,math.min(math.floor(count or 5),25))
    low,high=tonumber(low),tonumber(high)
    assert(low and high and low<high,"low must be less than high")
    local center=(best and best[parameter]) or ((low+high)/2)
    local span=(high-low)*0.25
    local a,b=clamp(center-span,low,high),clamp(center+span,low,high)
    local values={}
    for i=0,count-1 do values[#values+1]=a+(b-a)*i/(count-1) end
    return values
end
return Tuner
