-- Converts policy suggestions into bounded, inspectable action data.
-- Deliberately does not inject keys, touch live game state, or invoke remotes.
local Adapter={}
Adapter.__index=Adapter
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function number(v,fallback)
    return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge and v or fallback
end
function Adapter.new(config)
    config=config or {}
    return setmetatable({config=config,last={},sequence=0,diagnostics={}},Adapter)
end
function Adapter:reset()
    self.last={}
    self.sequence=0
    self.diagnostics={}
end
function Adapter:normalize(raw,car_id)
    raw=raw or {}
    local id=car_id or raw.car_id or "default"
    local prev=self.last[id] or {steer=0,throttle=0,boost=false,jump=false,dodge=false}
    local steer=clamp(number(raw.steer,0),-1,1)
    local throttle=clamp(number(raw.throttle,0),-1,1)
    local policy=self.config.policy or {}
    local max_steer=number(policy.max_steer_change,0.3)
    local max_throttle=number(policy.max_throttle_change,0.22)
    if raw.smoothing~=false then
        steer=clamp(steer,prev.steer-max_steer,prev.steer+max_steer)
        throttle=clamp(throttle,prev.throttle-max_throttle,prev.throttle+max_throttle)
    end
    local out={car_id=id,steer=steer,throttle=throttle,
        boost=raw.boost==true,jump=raw.jump==true,dodge=raw.dodge==true,
        handbrake=raw.handbrake==true,source=raw.source or "policy"}
    if raw.boost==true and raw.boost_reserve_ok==false then
        out.boost=false
        out.boost_block_reason="reserve"
    end
    if out.dodge and raw.dodge_available==false then
        out.dodge=false
        out.dodge_block_reason="cooldown"
    end
    if out.jump and raw.on_ground==false and raw.double_jump_available==false then
        out.jump=false
        out.jump_block_reason="jump_unavailable"
    end
    self.sequence=self.sequence+1
    out.sequence=self.sequence
    out.created_at=number(raw.time,0)
    self.last[id]={steer=steer,throttle=throttle,boost=out.boost,
        jump=out.jump,dodge=out.dodge}
    return out
end
function Adapter:validate(action)
    local errors={}
    if type(action)~="table" then return false,{"action must be a table"} end
    for _,key in ipairs({"steer","throttle"}) do
        if type(action[key])~="number" or action[key]<-1 or action[key]>1 then
            errors[#errors+1]=key.." must be numeric in [-1,1]"
        end
    end
    for _,key in ipairs({"boost","jump","dodge","handbrake"}) do
        if action[key]~=nil and type(action[key])~="boolean" then
            errors[#errors+1]=key.." must be boolean"
        end
    end
    if type(action.sequence)~="number" then errors[#errors+1]="sequence is required" end
    return #errors==0,errors
end
function Adapter:batch(raw_actions)
    local output={}
    for id,action in pairs(raw_actions or {}) do output[id]=self:normalize(action,id) end
    return output
end
function Adapter:diagnose(action,context)
    context=context or {}
    local warnings={}
    if action.boost and (context.boost or 0)<=0 then warnings[#warnings+1]="boost requested with empty tank" end
    if action.jump and context.on_ground==false and context.double_jump_available==false then
        warnings[#warnings+1]="jump requested while airborne without second jump"
    end
    if action.dodge and context.dodge_available==false then warnings[#warnings+1]="dodge is on cooldown" end
    if math.abs(action.steer or 0)>0.95 and math.abs(context.speed or 0)<5 then
        warnings[#warnings+1]="near-full steering at low speed may turn slowly"
    end
    local record={sequence=action.sequence,warnings=warnings}
    self.diagnostics[#self.diagnostics+1]=record
    if #self.diagnostics>128 then table.remove(self.diagnostics,1) end
    return record
end
function Adapter:export_state()
    local state={sequence=self.sequence,last={},diagnostics={}}
    for id,action in pairs(self.last) do
        state.last[id]={steer=action.steer,throttle=action.throttle,boost=action.boost,
            jump=action.jump,dodge=action.dodge}
    end
    for i,item in ipairs(self.diagnostics) do
        state.diagnostics[i]={sequence=item.sequence,warnings={}}
        for j,w in ipairs(item.warnings) do state.diagnostics[i].warnings[j]=w end
    end
    return state
end
function Adapter:import_state(state)
    assert(type(state)=="table","state must be a table")
    self.sequence=math.max(0,math.floor(number(state.sequence,0)))
    self.last=state.last or {}
    self.diagnostics=state.diagnostics or {}
end
return Adapter
