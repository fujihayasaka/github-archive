-- Lua script to mark a node as processed in the DAG stored in Redis
-- and move any nodes that are now eligible to the eligibleNodes list.
-- Unlike add_node, this script expects that the node kind be encoded
-- in the node ID.
-- Parameters:
--   KEYS[1] - The string that represents the node's kind and ID

local namespace = KEYS[1]
local IDs = ARGV

for i = 1, #IDs do
    local ID = IDs[i]

    redis.log(redis.LOG_NOTICE, "marking node as processed: " .. namespace .. ":" .. ID)

    if  redis.call("GET", namespace .. ":" .. ID .. ":processed" ) ~= "1" then
        -- Get all dependants from the set
        local dependants = redis.call("SMEMBERS", namespace .. ":" .. ID .. ":dependants")

        -- Iterate over each element in the set
        for j = 1, #dependants do
            local dependant = dependants[j]
            local dependencyKey = namespace .. ":" .. dependant .. ":dependencies"

            -- Get the current value of "dependant:dependencies"
            local currentDependencies = tonumber(redis.call("GET", dependencyKey))

            redis.log(redis.LOG_NOTICE, namespace .. ":" .. ID .. " dependant: " .. dependant .. " has " .. currentDependencies .. " dependencies")

            -- If "dependant:dependencies" exists and is greater than 0
            if currentDependencies and currentDependencies > 0 then
                -- Subtract 1 from "dependant:dependencies"
                local newDependencies = redis.call("DECR", dependencyKey)

                -- If the new value is 0, add the dependant to the "eligibleNodes" list
                -- as it means all of its dependencies have been processed
                if newDependencies == 0 then
                    redis.log(redis.LOG_NOTICE, "adding " .. dependant .. " to eligible nodes")
                    redis.call("SADD",  namespace .. ":eligible_nodes", dependant)
                end
            end
        end

        -- Delete ID from the "eligible nodes" set
        redis.call("SREM", namespace .. ":eligible_nodes", ID)

        -- Mark node as processed
        redis.call("SET", namespace .. ":" .. ID .. ":processed", "1")
    else
        redis.log(redis.LOG_NOTICE, "node already processed: " .. namespace .. ":" .. ID)
        -- Delete ID from the "eligible nodes" set
        redis.call("SREM", namespace .. ":eligible_nodes", ID)
    end
end

-- Return a success message
return "OK"