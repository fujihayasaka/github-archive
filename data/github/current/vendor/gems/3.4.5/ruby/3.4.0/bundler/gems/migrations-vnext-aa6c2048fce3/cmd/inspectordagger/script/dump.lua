-- Description: This script is used to dump the contents of the DAG
-- to a JSON string. The atomicity of a LUA script allows us to get
-- a consistent view of the DAG any time.
-- Input parameter
local namespace = KEYS[1]

-- Table to store the results
local result = {}

-- Part 1: Retrieve the members of the set in namespace:eligible_nodes
local eligible_nodes_key = namespace .. ":eligible_nodes"
local eligible_nodes = redis.call("SMEMBERS", eligible_nodes_key)
result["eligible_nodes"] = eligible_nodes

-- Part 2: Retrieve all integer values of each namespace:*:dependencies key
local dependencies_pattern = namespace .. ":*:dependencies"
local cursor = "0"
local dependencies = {}

repeat
    -- SCAN for keys matching the dependencies pattern
    local scan_result = redis.call("SCAN", cursor, "MATCH", dependencies_pattern)
    cursor = scan_result[1]  -- Update cursor
    local keys = scan_result[2]  -- Get the list of matching keys

    -- For each key found, retrieve its integer value
    for _, key in ipairs(keys) do
        local value = redis.call("GET", key)
        if value then
            dependencies[key] = tonumber(value)
        end
    end
until cursor == "0"

result["dependencies"] = dependencies

-- Part 3: Retrieve all members of each namespace:*:dependants set
local dependants_pattern = namespace .. ":*:dependants"
cursor = "0"
local dependants = {}

repeat
    -- SCAN for keys matching the dependants pattern
    local scan_result = redis.call("SCAN", cursor, "MATCH", dependants_pattern)
    cursor = scan_result[1]
    local keys = scan_result[2]

    -- For each key found, retrieve the set members
    for _, key in ipairs(keys) do
        local members = redis.call("SMEMBERS", key)
        dependants[key] = members
    end
until cursor == "0"

result["dependants"] = dependants

-- Return the final result table
return cjson.encode(result)