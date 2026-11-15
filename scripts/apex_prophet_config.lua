-- APEX × Prophet configuration.
-- Pure Lua: safe for offline tests and private Roblox Studio simulations.
local Config = {}

Config.version = "1.0.0"
Config.seed = 41721
Config.fixed_dt = 1 / 60
Config.max_simulation_time = 12
Config.field = {
    half_length = 100,
    half_width = 55,
    floor_z = 0,
    ceiling_z = 42,
    goal_half_width = 18,
    goal_height = 12,
    goal_depth = 8,
    wall_restitution = 0.68,
    floor_restitution = 0.62,
}
Config.ball = {
    radius = 2.1,
    gravity = 42,
    linear_drag = 0.018,
    rolling_drag = 0.9,
    max_speed = 150,
    bounce_min_speed = 4,
}
Config.car = {
    radius = 2.2,
    max_speed = 68,
    acceleration = 42,
    braking = 58,
    boost_acceleration = 31,
    boost_speed = 88,
    boost_drain = 32,
    boost_regen = 8,
    jump_impulse = 17,
    dodge_impulse = 25,
    air_control = 0.36,
    turn_rate = 3.1,
}
Config.policy = {
    prediction_horizon = 2.4,
    prediction_step = 0.06,
    intercept_sample_count = 30,
    shot_samples = 15,
    danger_radius = 34,
    shadow_distance = 20,
    teammate_spacing = 18,
    boost_reserve = 22,
    aerial_min_height = 11,
    aerial_max_height = 34,
    low_boost_threshold = 28,
    max_throttle_change = 0.22,
    max_steer_change = 0.3,
}
Config.scoring = {
    goal = 1000,
    shot = 24,
    clear = 20,
    intercept = 12,
    possession = 7,
    boost = 5,
    teammate_collision = -35,
    own_goal_risk = -120,
    wasted_boost = -6,
    stale_action = -10,
}
Config.limits = {
    max_players = 8,
    max_boost_pads = 64,
    max_history = 240,
    max_scenarios = 500,
    max_errors = 32,
}
function Config.copy(source)
    if type(source) ~= "table" then return source end
    local out = {}
    for key, value in pairs(source) do out[key] = Config.copy(value) end
    return out
end
function Config.merge(base, overrides)
    local out = Config.copy(base or {})
    for key, value in pairs(overrides or {}) do
        if type(value) == "table" and type(out[key]) == "table" then
            out[key] = Config.merge(out[key], value)
        else
            out[key] = Config.copy(value)
        end
    end
    return out
end
function Config.validate(config)
    local errors = {}
    config = config or Config
    local function positive(path, value)
        if type(value) ~= "number" or value <= 0 then
            errors[#errors + 1] = path .. " must be a positive number"
        end
    end
    positive("fixed_dt", config.fixed_dt)
    positive("max_simulation_time", config.max_simulation_time)
    positive("field.half_length", config.field and config.field.half_length)
    positive("field.half_width", config.field and config.field.half_width)
    positive("ball.radius", config.ball and config.ball.radius)
    positive("ball.max_speed", config.ball and config.ball.max_speed)
    positive("car.max_speed", config.car and config.car.max_speed)
    if config.policy then
        positive("policy.prediction_horizon", config.policy.prediction_horizon)
        positive("policy.prediction_step", config.policy.prediction_step)
    else
        errors[#errors + 1] = "policy section is required"
    end
    return #errors == 0, errors
end
return Config
