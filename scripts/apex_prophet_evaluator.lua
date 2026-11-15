-- Evaluation and benchmark utilities for offline policy experiments.
local Evaluator = {}
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function vec(v) return {x=(v and v.x) or 0,y=(v and v.y) or 0,z=(v and v.z) or 0} end
local function distance(a,b)
    a,b=vec(a),vec(b)
    local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z
    return math.sqrt(x*x+y*y+z*z)
end
local function average(values)
    if #values==0 then return 0 end
    local sum=0
    for _,v in ipairs(values) do sum=sum+v end
    return sum/#values
end
local function percentile(values,p)
    if #values==0 then return 0 end
    local sorted={}
    for i,v in ipairs(values) do sorted[i]=v end
    table.sort(sorted)
    local index=math.max(1,math.min(#sorted,math.ceil(#sorted*p)))
    return sorted[index]
end
function Evaluator.new(options)
    options=options or {}
    return setmetatable({options=options,episodes={},active=nil},{__index=Evaluator})
end
function Evaluator:start_episode(meta)
    self.active={meta=meta or {},frames=0,goals_for=0,goals_against=0,
        touches=0,shots=0,shots_on_target=0,intercepts=0,missed_intercepts=0,
        boost_used=0,boost_collected=0,collision_count=0,own_goal_risks=0,
        action_changes=0,stale_actions=0,decision_times={},position_errors={},
        ball_distances={},rewards={},events={}}
    return self.active
end
function Evaluator:observe(frame)
    local e=self.active
    assert(e,"start_episode must be called before observe")
    frame=frame or {}
    e.frames=e.frames+1
    if type(frame.decision_ms)=="number" then e.decision_times[#e.decision_times+1]=frame.decision_ms end
    if type(frame.position_error)=="number" then e.position_errors[#e.position_errors+1]=frame.position_error end
    if type(frame.ball_distance)=="number" then e.ball_distances[#e.ball_distances+1]=frame.ball_distance end
    if type(frame.reward)=="number" then e.rewards[#e.rewards+1]=frame.reward end
    local counts={"touches","shots","shots_on_target","intercepts","missed_intercepts",
        "boost_used","boost_collected","collision_count","own_goal_risks","action_changes","stale_actions"}
    for _,key in ipairs(counts) do
        if type(frame[key])=="number" then e[key]=e[key]+frame[key] end
    end
    if frame.event then e.events[#e.events+1]=frame.event end
    return e.frames
end
function Evaluator:finish_episode(result)
    local e=self.active
    assert(e,"no active episode")
    result=result or {}
    e.goals_for=result.goals_for or e.goals_for
    e.goals_against=result.goals_against or e.goals_against
    e.duration=result.duration or e.frames/60
    e.goal_difference=e.goals_for-e.goals_against
    e.average_decision_ms=average(e.decision_times)
    e.p95_decision_ms=percentile(e.decision_times,0.95)
    e.average_position_error=average(e.position_errors)
    e.p95_position_error=percentile(e.position_errors,0.95)
    e.average_ball_distance=average(e.ball_distances)
    e.total_reward=0
    for _,r in ipairs(e.rewards) do e.total_reward=e.total_reward+r end
    e.touch_rate=e.duration>0 and e.touches/e.duration or 0
    e.shot_accuracy=e.shots>0 and e.shots_on_target/e.shots or 0
    e.intercept_accuracy=(e.intercepts+e.missed_intercepts)>0
        and e.intercepts/(e.intercepts+e.missed_intercepts) or 0
    e.stale_action_rate=e.frames>0 and e.stale_actions/e.frames or 0
    self.episodes[#self.episodes+1]=e
    self.active=nil
    return e
end
function Evaluator:summarize()
    local summary={episodes=#self.episodes,frames=0,goals_for=0,goals_against=0,
        total_reward=0,shots=0,shots_on_target=0,intercepts=0,missed_intercepts=0,
        collisions=0,own_goal_risks=0,mean_decision_ms=0,p95_decision_ms=0,
        mean_position_error=0,mean_touch_rate=0,mean_shot_accuracy=0,
        mean_intercept_accuracy=0,mean_stale_action_rate=0,win_rate=0,
        episode_goal_differences={}}
    local times,errors={},{}
    local wins=0
    for _,e in ipairs(self.episodes) do
        summary.frames=summary.frames+e.frames
        summary.goals_for=summary.goals_for+e.goals_for
        summary.goals_against=summary.goals_against+e.goals_against
        summary.total_reward=summary.total_reward+e.total_reward
        summary.shots=summary.shots+e.shots
        summary.shots_on_target=summary.shots_on_target+e.shots_on_target
        summary.intercepts=summary.intercepts+e.intercepts
        summary.missed_intercepts=summary.missed_intercepts+e.missed_intercepts
        summary.collisions=summary.collisions+e.collision_count
        summary.own_goal_risks=summary.own_goal_risks+e.own_goal_risks
        summary.mean_touch_rate=summary.mean_touch_rate+e.touch_rate
        summary.mean_shot_accuracy=summary.mean_shot_accuracy+e.shot_accuracy
        summary.mean_intercept_accuracy=summary.mean_intercept_accuracy+e.intercept_accuracy
        summary.mean_stale_action_rate=summary.mean_stale_action_rate+e.stale_action_rate
        summary.episode_goal_differences[#summary.episode_goal_differences+1]=e.goal_difference
        if e.goal_difference>0 then wins=wins+1 end
        for _,v in ipairs(e.decision_times) do times[#times+1]=v end
        for _,v in ipairs(e.position_errors) do errors[#errors+1]=v end
    end
    local n=math.max(1,#self.episodes)
    summary.mean_touch_rate=summary.mean_touch_rate/n
    summary.mean_shot_accuracy=summary.mean_shot_accuracy/n
    summary.mean_intercept_accuracy=summary.mean_intercept_accuracy/n
    summary.mean_stale_action_rate=summary.mean_stale_action_rate/n
    summary.mean_decision_ms=average(times)
    summary.p95_decision_ms=percentile(times,0.95)
    summary.mean_position_error=average(errors)
    summary.win_rate=wins/n
    summary.goal_difference=summary.goals_for-summary.goals_against
    summary.shot_accuracy=summary.shots>0 and summary.shots_on_target/summary.shots or 0
    summary.intercept_accuracy=(summary.intercepts+summary.missed_intercepts)>0
        and summary.intercepts/(summary.intercepts+summary.missed_intercepts) or 0
    return summary
end
function Evaluator.compare(candidate, baseline)
    candidate,baseline=candidate or {},baseline or {}
    local metrics={"win_rate","goal_difference","shot_accuracy","intercept_accuracy",
        "mean_position_error","mean_decision_ms","mean_stale_action_rate","own_goal_risks"}
    local lower_is_better={mean_position_error=true,mean_decision_ms=true,
        mean_stale_action_rate=true,own_goal_risks=true}
    local out={}
    for _,metric in ipairs(metrics) do
        local a,b=candidate[metric] or 0,baseline[metric] or 0
        local delta=a-b
        out[metric]={candidate=a,baseline=b,delta=delta,
            improved=lower_is_better[metric] and delta<0 or (not lower_is_better[metric] and delta>0)}
    end
    return out
end
function Evaluator.rank_candidates(results, weights)
    weights=weights or {win_rate=5,goal_difference=2,shot_accuracy=1,
        intercept_accuracy=1,mean_position_error=-0.05,mean_decision_ms=-0.02,
        own_goal_risks=-3,mean_stale_action_rate=-2}
    local ranked={}
    for name,metrics in pairs(results or {}) do
        local score=0
        for key,weight in pairs(weights) do score=score+(metrics[key] or 0)*weight end
        ranked[#ranked+1]={name=name,score=score,metrics=metrics}
    end
    table.sort(ranked,function(a,b) return a.score>b.score end)
    return ranked
end
function Evaluator.validate_metrics(metrics)
    local issues={}
    if type(metrics)~="table" then return false,{"metrics must be a table"} end
    for key,value in pairs(metrics) do
        if type(value)=="number" and (value~=value or value==math.huge or value==-math.huge) then
            issues[#issues+1]=key.." is not finite"
        end
    end
    for _,key in ipairs({"win_rate","shot_accuracy","intercept_accuracy","mean_stale_action_rate"}) do
        if metrics[key] and (metrics[key]<0 or metrics[key]>1) then
            issues[#issues+1]=key.." must be between 0 and 1"
        end
    end
    return #issues==0,issues
end
function Evaluator.bootstrap_mean(values, rounds, seed)
    rounds=rounds or 500
    local state=seed or 981723
    local function random_index(n)
        state=(state*48271)%2147483647
        return math.floor((state/2147483647)*n)+1
    end
    local means={}
    for i=1,rounds do
        local sample={}
        for _=1,#values do sample[#sample+1]=values[random_index(#values)] end
        means[i]=average(sample)
    end
    return {mean=average(values),low=percentile(means,0.025),high=percentile(means,0.975),rounds=rounds}
end
function Evaluator.distance_to_ball(car, ball)
    return distance(car and car.position, ball and ball.position)
end
function Evaluator.action_sanity(action)
    action=action or {}
    local issues={}
    for _,key in ipairs({"steer","throttle"}) do
        if type(action[key])~="number" then issues[#issues+1]=key.." must be numeric"
        elseif action[key]<-1 or action[key]>1 then issues[#issues+1]=key.." out of range" end
    end
    if action.boost~=nil and type(action.boost)~="boolean" then issues[#issues+1]="boost must be boolean" end
    return #issues==0,issues
end
return Evaluator
