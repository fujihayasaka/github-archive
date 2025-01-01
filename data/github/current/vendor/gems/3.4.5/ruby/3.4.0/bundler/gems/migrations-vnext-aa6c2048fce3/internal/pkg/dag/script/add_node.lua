-- Lua script to add a node and its dependencies to the DAG stored in Redis
-- Parameters:
--   KEYS[1] - This is the prefix for all keys in the DAG.
--   KEYS[2] - The string that represents the node's kind.
--   KEYS[3] - The string that represents the node's ID
--   ARGV    - The array of string IDs (dependencies)

local namespace = KEYS[1]
local nodeKind = KEYS[2]
local nodeID = KEYS[3]
local dependencies = ARGV
local ID = nodeKind .. ":" .. nodeID

redis.log(redis.LOG_NOTICE, "calling add node: " .. namespace .. ":" .. ID .. " with dependencies: " .. table.concat(dependencies, ", "))

-- Filter the dependencies array to only include those whose "<dependency>:processed" key does not exist
local unfulfilledDeps = {}

for i = 1, #dependencies do
    local dependency = dependencies[i]
    local processedKey = namespace .. ":" .. dependency .. ":processed"

    -- Check if the processed key exists
    if redis.call("EXISTS", processedKey) == 0 then
        -- If the processed key does not exist, add the dependency to the unfulfilled dependencies list
        table.insert(unfulfilledDeps, dependency)
    end
end

redis.log(redis.LOG_NOTICE, "calling add node: " .. namespace .. ":" .. ID .. " with unfulfilled dependencies: " .. table.concat(unfulfilledDeps, ", "))

-- Check if dependencies are empty
if #unfulfilledDeps == 0 then
    -- Add the ID to eligibleNodes
    redis.log(redis.LOG_NOTICE, "adding: " .. ID .. " to eligible nodes")
    redis.call("SADD", namespace .. ":eligible_nodes", ID)
    return "OK"
end

-- Entry has unfulfilled dependencies

-- Create an entry with key "ID:dependencies"
-- and the value as the cardinality of its dependencies
local key = namespace .. ":" .. ID .. ":dependencies"
local dependencyCount = #unfulfilledDeps
redis.call("SET", key, dependencyCount)

-- For each dependency, update its dependant set with ID
for i = 1, #dependencies do
    local dependantKey = namespace .. ":" .. dependencies[i] .. ":dependants"
    redis.call("SADD", dependantKey, ID)
end

-- Return a success message
return "OK"
