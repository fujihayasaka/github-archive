-- From <https://github.com/earrrl/earrrl-ruby/blob/main/lib/earrrl/script_loader.rb>
--
-- Adjust an actor's usage rate by `charge` units of cost if they are not in
-- quota violation.
--
-- Returns a string containing a result and four numbers, separated by spaces:
-- * whether the user was in quota violation at the requested time
-- * the current time (pass this to redis_post_query.lua later)
-- * the amount of pre-charge that was applied (0 or `charge`)
-- * the estimated rate (cost/second) over the past ~1 minute
-- * the estimated rate (cost/second) over the past ~4 hours
--
-- If the user is in quota violation, the pre-charge is NOT applied.
--
-- Note that the result and rates that are returned are from BEFORE the
-- pre-charge is applied.
--
-- Usage:
--   SCRIPT LOAD "<content-of-this-file>"
--   EVALSHA <script-load-sha> 1 <actor-id> <charge>

-- Calculates the current rate as of `now`, both before and after a pre-charge
-- of `increment` is applied.  Does not update the Redis key for this quota
-- bucket.
local function calculate_charge(key, now, half_life_seconds, increment)
    -- Load previous state, if any.
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

    -- Adjust the rate estimate to give the user credit for however long
    -- they've gone without sending a request. We choose exponential decay,
    -- exp(-λ Δt). Lambda is the exponential decay constant; see
    -- <https://en.wikipedia.org/wiki/Exponential_decay>.
    local lambda = math.log(2.0) / half_life_seconds
    local old_rate = R * math.exp(-lambda * (now - T))
    local new_rate = old_rate + lambda * increment
    return old_rate, new_rate
end

local function update_rate(key, now, half_life_seconds, rate)
    redis.call("HSET", key, "R", rate, "T", now)
    -- After 30 half-lives, the value will be approximately 0, not worth keeping.
    redis.call("EXPIRE", key, 30 * half_life_seconds)
end

-- Redis will send all scalar parameters to us as strings.  Lua will implicitly
-- convert those to integers when performing arithmetic, but NOT when performing
-- comparisons.  So let's explicitly convert them to numbers here so that we
-- don't confuse ourselves down the line.
local charge = tonumber(ARGV[1])
local time = tonumber(ARGV[2])
local short_term_half_life_seconds = tonumber(ARGV[3])
local short_term_rate_limit = tonumber(ARGV[4])
local long_term_half_life_seconds = tonumber(ARGV[5])
local long_term_rate_limit = tonumber(ARGV[6])

-- Get current time in Unix seconds. Redis returns this as the array
-- `{seconds, microseconds}`; see <https://redis.io/commands/time>.
local now
if time == 0 then
   local time_array = redis.call("TIME")
   now = time_array[1] + 0.000001 * time_array[2]
else
   now = time
end

local short_term_key = "usage." .. KEYS[1] .. ".short"
local long_term_key = "usage." .. KEYS[1] .. ".long"
local short_term_old_rate, short_term_new_rate = calculate_charge(short_term_key, now, short_term_half_life_seconds, charge)
local long_term_old_rate, long_term_new_rate = calculate_charge(long_term_key, now, long_term_half_life_seconds, charge)

-- Determine whether the user was already in violation.
local result = "ok"
if short_term_old_rate > short_term_rate_limit then
    result = "reject-short"
elseif long_term_old_rate > long_term_rate_limit then
    result = "reject-long"
end

-- Update the Redis state for this query bucket, but do NOT apply the pre-charge
-- if the user was in violation.  (We still need to update the Redis keys to
-- advance forward to the current time and credit any rate decay that has
-- occurred.)
local charge_applied = charge
if result == "ok" then
    update_rate(short_term_key, now, short_term_half_life_seconds, short_term_new_rate)
    update_rate(long_term_key, now, long_term_half_life_seconds, long_term_new_rate)
else
    -- We could update the Redis keys to hold `old_rate` here, but it won't
    -- change the results of this or any future rate limit checks, so we skip
    -- that step to avoid the round trip back to Redis.
    charge_applied = 0
end

-- Return as a string. (Lua supports returning an array of floats here, but
-- Redis doesn't have a float type. It would convert the numbers to integers.)
return result .. " " .. now .. " " .. charge_applied .. " " .. short_term_old_rate .. " " .. long_term_old_rate
