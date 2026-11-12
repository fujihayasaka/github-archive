# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module TaskLocks
      # Acquire a task lock.
      module AcquireTaskLockMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.task_locks.acquire"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "holder" => "String!",
          "name" => "String!",
          "ttl" => "Int!",
        }

        # Acquire a task lock.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param holder [String] The holder requesting the lock.
        # @param name [String] Task lock name.
        # @param ttl [Integer] For how many seconds the task lock is to be valid.
        #
        # @return [Hash]
        def self.execute(client:, context: {}, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          query = build_query(variables)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "acquireTaskLock")
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        #
        # @return [String] The mutation query
        def self.build_query(variables, **kwargs)
          <<~GRAPHQL
            mutation acquireTaskLock#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              acquireTaskLock(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                taskLock {
                  id
                  name
                  expiresAt
                  holder
                }
              }
            }
          GRAPHQL
        end
      end
    end

    class TaskLocksQueryBinder < QueryBinder
      # Acquire a task lock.
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param holder [String] The holder requesting the lock.
      # @param name [String] Task lock name.
      # @param ttl [Integer] For how many seconds the task lock is to be valid.
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def acquire(**kwargs)
        Response.new Client::TaskLocks::AcquireTaskLockMutation.execute(client: client, **kwargs)
      end
    end
  end
end
