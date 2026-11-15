-- Deterministic, intentionally simplified offline car-soccer simulator.
-- This module does not access Roblox instances, live games, remotes, or input APIs.
local Simulator = {}
Simulator.__index = Simulator

local function vec(x, y, z)
    return { x = x or 0, y = y or 0, z = z or 0 }
end
local function copy(v)
    return vec(v and v.x, v and v.y, v and v.z)
end
local function add(a, b) return vec(a.x+b.x, a.y+b.y, a.z+b.z) end
local function scale(a, s) return vec(a.x*s, a.y*s, a.z*s) end
local function dot(a, b) return a.x*b.x + a.y*b.y + a.z*b.z end
local function magnitude(a) return math.sqrt(dot(a,a)) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function normalize(a)
    local m = magnitude(a)
    if m < 1e-8 then return vec() end
    return scale(a, 1/m)
end
local function limit(a, max_value)
    local m = magnitude(a)
    if m <= max_value or m < 1e-8 then return copy(a) end
    return scale(a, max_value/m)
end
local function sign(v) return v < 0 and -1 or (v > 0 and 1 or 0) end

Simulator.vec = vec
Simulator.copy_vector = copy

function Simulator.new(config, seed)
    local self = setmetatable({}, Simulator)
    self.config = config or {}
    self.field = self.config.field or {half_length=100,half_width=55,ceiling_z=42,
        goal_half_width=18,goal_height=12,goal_depth=8,wall_restitution=0.68,floor_restitution=0.62}
    self.ball_config = self.config.ball or {radius=2.1,gravity=42,linear_drag=0.018,
        rolling_drag=0.9,max_speed=150,bounce_min_speed=4}
    self.car_config = self.config.car or {max_speed=68,acceleration=42,braking=58,
        boost_acceleration=31,boost_speed=88,boost_drain=32,boost_regen=8,
        jump_impulse=17,dodge_impulse=25,air_control=0.36,turn_rate=3.1}
    self.dt = (self.config and self.config.fixed_dt) or 1/60
    self.time = 0
    self.tick = 0
    self.score = { blue=0, orange=0 }
    self.events = {}
    self.rng_state = seed or (self.config.seed or 41721)
    self.state = {
        ball = { position=vec(), velocity=vec(), radius=self.ball_config.radius },
        cars = {},
        boost_pads = {},
        match = { time=0, blue_score=0, orange_score=0, last_touch=nil },
    }
    return self
end

function Simulator:random()
    self.rng_state = (self.rng_state * 48271) % 2147483647
    return self.rng_state / 2147483647
end

function Simulator:add_car(car)
    assert(type(car) == "table", "car must be a table")
    local item = {
        id = car.id or ("car_" .. tostring(#self.state.cars + 1)),
        team = car.team or "blue",
        position = copy(car.position or vec()),
        velocity = copy(car.velocity or vec()),
        yaw = car.yaw or 0,
        boost = clamp(car.boost or 50, 0, 100),
        on_ground = car.on_ground ~= false,
        demoed = car.demoed == true,
        jump_cooldown = 0,
        dodge_cooldown = 0,
        last_action = {},
    }
    self.state.cars[#self.state.cars + 1] = item
    return item
end

function Simulator:add_boost_pad(pad)
    self.state.boost_pads[#self.state.boost_pads + 1] = {
        id = pad.id or ("pad_" .. tostring(#self.state.boost_pads + 1)),
        position = copy(pad.position or vec()),
        amount = pad.amount or 12,
        active = pad.active ~= false,
        respawn = pad.respawn or 4,
        timer = 0,
    }
end

function Simulator:set_ball(position, velocity)
    self.state.ball.position = copy(position or vec())
    self.state.ball.velocity = copy(velocity or vec())
end

function Simulator:set_state(state)
    assert(type(state) == "table", "state must be a table")
    self.state = state
    self.state.ball = self.state.ball or {position=vec(),velocity=vec(),radius=self.ball_config.radius}
    self.state.cars = self.state.cars or {}
    self.state.boost_pads = self.state.boost_pads or {}
    self.state.match = self.state.match or {time=self.time,blue_score=0,orange_score=0}
end

function Simulator:snapshot()
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = clone(v) end
        return out
    end
    return clone(self.state)
end

function Simulator:record_event(kind, data)
    self.events[#self.events + 1] = {time=self.time, tick=self.tick, kind=kind, data=data or {}}
    if #self.events > 256 then table.remove(self.events, 1) end
end

function Simulator:step_ball(dt)
    local b, c, f = self.state.ball, self.ball_config, self.field
    b.velocity.z = b.velocity.z - c.gravity * dt
    b.velocity = scale(b.velocity, math.max(0, 1-c.linear_drag*dt))
    b.velocity = limit(b.velocity, c.max_speed)
    b.position = add(b.position, scale(b.velocity, dt))
    if b.position.z < b.radius then
        b.position.z = b.radius
        if math.abs(b.velocity.z) > c.bounce_min_speed then
            b.velocity.z = math.abs(b.velocity.z) * f.floor_restitution
            self:record_event("ball_bounce", {surface="floor",speed=math.abs(b.velocity.z)})
        else
            b.velocity.z = 0
        end
        b.velocity.x = b.velocity.x * math.max(0,1-c.rolling_drag*dt*0.12)
        b.velocity.y = b.velocity.y * math.max(0,1-c.rolling_drag*dt*0.12)
    end
    if b.position.z > f.ceiling_z - b.radius then
        b.position.z = f.ceiling_z - b.radius
        b.velocity.z = -math.abs(b.velocity.z) * f.wall_restitution
        self:record_event("ball_bounce", {surface="ceiling"})
    end
    if math.abs(b.position.y) > f.half_width - b.radius then
        b.position.y = sign(b.position.y) * (f.half_width - b.radius)
        b.velocity.y = -sign(b.velocity.y) * math.abs(b.velocity.y) * f.wall_restitution
        self:record_event("ball_bounce", {surface="side_wall"})
    end
    local near_goal = math.abs(b.position.y) < f.goal_half_width
        and b.position.z < f.goal_height
    if math.abs(b.position.x) > f.half_length - b.radius and not near_goal then
        b.position.x = sign(b.position.x) * (f.half_length - b.radius)
        b.velocity.x = -sign(b.position.x) * math.abs(b.velocity.x) * f.wall_restitution
        self:record_event("ball_bounce", {surface="end_wall"})
    elseif near_goal and math.abs(b.position.x) > f.half_length + f.goal_depth then
        local team = b.position.x > 0 and "blue" or "orange"
        self.score[team] = (self.score[team] or 0) + 1
        self:record_event("goal", {team=team})
        b.position, b.velocity = vec(), vec()
        self.state.match.blue_score = self.score.blue
        self.state.match.orange_score = self.score.orange
    end
end

function Simulator:step_car(car, action, dt)
    local c = self.car_config
    action = action or {}
    car.jump_cooldown = math.max(0, (car.jump_cooldown or 0)-dt)
    car.dodge_cooldown = math.max(0, (car.dodge_cooldown or 0)-dt)
    if car.demoed then
        car.velocity = vec()
        return
    end
    local steer = clamp(action.steer or 0, -1, 1)
    local throttle = clamp(action.throttle or 0, -1, 1)
    car.yaw = (car.yaw or 0) + steer * c.turn_rate * dt
    local forward = vec(math.cos(car.yaw), math.sin(car.yaw), 0)
    local speed_forward = dot(car.velocity, forward)
    local accel = throttle >= 0 and c.acceleration or c.braking
    local boost = action.boost == true and car.boost > 0
    local control = car.on_ground and 1 or c.air_control
    car.velocity = add(car.velocity, scale(forward, throttle*accel*control*dt))
    if boost then
        car.velocity = add(car.velocity, scale(forward, c.boost_acceleration*control*dt))
        car.boost = math.max(0, car.boost-c.boost_drain*dt)
    elseif action.regen ~= false then
        car.boost = math.min(100, car.boost+c.boost_regen*dt)
    end
    if action.jump and car.on_ground and car.jump_cooldown <= 0 then
        car.velocity.z = c.jump_impulse
        car.on_ground = false
        car.jump_cooldown = 0.22
        self:record_event("jump", {car_id=car.id})
    end
    if action.dodge and car.dodge_cooldown <= 0 then
        car.velocity = add(car.velocity, scale(forward, c.dodge_impulse))
        car.velocity.z = math.max(car.velocity.z, c.jump_impulse*0.45)
        car.on_ground = false
        car.dodge_cooldown = 1.1
        self:record_event("dodge", {car_id=car.id})
    end
    -- Apply vertical gravity after jump/dodge impulses. Without this, airborne
    -- cars keep rising forever in the toy simulator and jump tuning is meaningless.
    if not car.on_ground then
        car.velocity.z = car.velocity.z - (c.gravity or self.ball_config.gravity or 42) * dt
    end
    local max_speed = boost and c.boost_speed or c.max_speed
    car.velocity = limit(car.velocity, max_speed)
    car.position = add(car.position, scale(car.velocity, dt))
    if car.position.z <= 0 then
        car.position.z = 0
        car.velocity.z = math.max(0, car.velocity.z)
        car.on_ground = true
    end
    local f = self.field
    car.position.x = clamp(car.position.x, -f.half_length, f.half_length)
    car.position.y = clamp(car.position.y, -f.half_width, f.half_width)
    car.last_action = {steer=steer,throttle=throttle,boost=boost,
        jump=action.jump==true,dodge=action.dodge==true}
end

function Simulator:resolve_car_ball_collisions()
    local ball = self.state.ball
    local carConfig = self.car_config
    local ballRadius = ball.radius or self.ball_config.radius or 2.1
    local carRadius = carConfig.radius or 2.2
    local combinedRadius = ballRadius + carRadius
    for _, car in ipairs(self.state.cars) do
        if not car.demoed then
            local delta = {
                x = ball.position.x - car.position.x,
                y = ball.position.y - car.position.y,
                z = ball.position.z - car.position.z,
            }
            local distance = magnitude(delta)
            if distance < combinedRadius then
                local normal = distance > 1e-8 and scale(delta, 1 / distance) or vec(1, 0, 0)
                -- Separate overlapping spheres before applying an impulse so the
                -- same contact cannot accumulate unbounded force each frame.
                ball.position = add(car.position, scale(normal, combinedRadius + 0.001))
                local relativeVelocity = {
                    x = ball.velocity.x - car.velocity.x,
                    y = ball.velocity.y - car.velocity.y,
                    z = ball.velocity.z - car.velocity.z,
                }
                local closingSpeed = dot(relativeVelocity, normal)
                if closingSpeed < 0 then
                    local restitution = 0.45
                    ball.velocity = add(ball.velocity,
                        scale(normal, -(1 + restitution) * closingSpeed))
                    ball.velocity = limit(ball.velocity, self.ball_config.max_speed or 150)
                    self.state.match.last_touch = car.id
                    self:record_event("car_ball_touch", {
                        car_id = car.id,
                        impulse = -(1 + restitution) * closingSpeed,
                    })
                end
            end
        end
    end
end

function Simulator:step(actions, dt)
    dt = dt or self.dt
    assert(type(dt) == "number" and dt > 0 and dt <= 0.25, "dt must be in (0, 0.25]")
    actions = actions or {}
    self:step_ball(dt)
    for _, car in ipairs(self.state.cars) do
        self:step_car(car, actions[car.id] or actions.default or {}, dt)
    end
    self:resolve_car_ball_collisions()
    for _, pad in ipairs(self.state.boost_pads) do
        if not pad.active then
            pad.timer = math.max(0, (pad.timer or 0)-dt)
            if pad.timer <= 0 then pad.active = true end
        else
            for _, car in ipairs(self.state.cars) do
                local delta = add(car.position, scale(pad.position,-1))
                if magnitude(delta) < 4.5 and car.boost < 100 then
                    car.boost = math.min(100, car.boost+pad.amount)
                    pad.active, pad.timer = false, pad.respawn
                    self:record_event("boost_pickup", {car_id=car.id,pad_id=pad.id})
                    break
                end
            end
        end
    end
    self.time, self.tick = self.time+dt, self.tick+1
    self.state.match.time = self.time
    return self.state
end

function Simulator:run(duration, policy)
    local end_time = self.time + (duration or 1)
    while self.time < end_time do
        local actions = {}
        for _, car in ipairs(self.state.cars) do
            if policy then actions[car.id] = policy(self:snapshot(), car.id, self.time) end
        end
        self:step(actions, math.min(self.dt, end_time-self.time))
    end
    return self:snapshot()
end

function Simulator:reset()
    self.time, self.tick = 0, 0
    self.score = {blue=0,orange=0}
    self.events = {}
    self.state = {ball={position=vec(),velocity=vec(),radius=self.ball_config.radius},
        cars={},boost_pads={},match={time=0,blue_score=0,orange_score=0,last_touch=nil}}
end

return Simulator
