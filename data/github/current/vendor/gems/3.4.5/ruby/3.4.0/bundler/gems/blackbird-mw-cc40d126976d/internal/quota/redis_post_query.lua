-- From <https://github.com/earrrl/earrrl-ruby/blob/main/lib/earrrl/script_loader.rb>
--
-- Effectively undo the side effect of previously running redis_pre_query.lua,
-- and replace it with a new charge of <corrected-cost>. <start-time> is the
-- timestamp returned when running redis_pre_query.lua earrrlier.
--
-- Usage:
--   SCRIPT LOAD "<content-of-this-file>"
--   EVALSHA <script-load-sha> 1 <actor-id> <start-time> <charged-cost> <corrected-cost>

local function adjust_rate(key, half_life_seconds, t_then, charge_then, t_now, charge_now)
    -- Load existing state.
    local flat_NT = redis.pcall("HGETALL", key)
    local R = 0.0  -- saved rate estimate from last time
    local T = 0.0  -- timestamp when we stored that estimate
    if #flat_NT == 4 and flat_NT[1] == "R" and flat_NT[3] == "T" then
        R = tonumber(flat_NT[2])
        T = tonumber(flat_NT[4])
    end
    if R == 0.0 and T == 0.0 and (flat_NT["err"] or #flat_NT > 0) then
        -- something is wrong with this key; delete it and start over
        redis.call("DEL", key)
    end

    -- First bring our rate estimate R up to the present.
    local lambda = math.log(2.0) / half_life_seconds
    R = R * math.exp(-lambda * (t_now - T))

    -- Compute adjusted rate by subtracting the old charge and adding the new one.
    local decay = math.exp(-lambda * (t_now - t_then))
    local adjustment = charge_now - charge_then * decay
    local rate = R + lambda * adjustment

    -- Update rate estimate. BUG: if `R` is set to `inf`, user is in violation forever.
    redis.call("HSET", key, "R", rate, "T", t_now)
    -- After 30 half-lives, the value will be approximately 0, not worth keeping.
    redis.call("EXPIRE", key, 30 * half_life_seconds)
end

-- Redis will send all scalar parameters to us as strings.  Lua will implicitly
-- convert those to integers when performing arithmetic, but NOT when performing
-- comparisons.  So let's explicitly convert them to numbers here so that we
-- don't confuse ourselves down the line.
local t_then = tonumber(ARGV[1])
local charge_then = tonumber(ARGV[2])
local charge_now = tonumber(ARGV[3])
local time = tonumber(ARGV[4])
local short_term_half_life_seconds = tonumber(ARGV[5])
local long_term_half_life_seconds = tonumber(ARGV[6])

-- Get current time in Unix seconds. Redis returns this as the array
-- `{seconds, microseconds}`; see <https://redis.io/commands/time>.
local now
if time == 0 then
   local time_array = redis.call("TIME")
   now = time_array[1] + 0.000001 * time_array[2]
else
   now = time
end

adjust_rate("usage." .. KEYS[1] .. ".short", short_term_half_life_seconds, t_then, charge_then, now, charge_now)
adjust_rate("usage." .. KEYS[1] .. ".long", long_term_half_life_seconds, t_then, charge_then, now, charge_now)

-- Go's Redis client library treats `nil` as an error, so return a non-nil value.
return "ok"
