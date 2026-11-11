# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Subscriptions
      # Updates a subscription
      module UpdateSubscriptionMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.subscriptions.update_subscription"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "id" => "ID!",
          "lastProcessed" => "ISO8601DateTime",
        }

        # Updates a subscription
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param id [String] The ID of the subscription.
        # @param last_processed [Time] The time a report was last processed.
        # @param detail_fragment [String] GraphQL detail fragment for the model
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: SubscriptionsQueryBinder::SUBSCRIPTION_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "updateSubscription")
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        #
        # @return [String] The mutation query
        def self.build_query(variables, detail_fragment: SubscriptionsQueryBinder::SUBSCRIPTION_DETAIL_FRAGMENT, **kwargs)
          <<~GRAPHQL
            mutation updateSubscription#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              updateSubscription(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                subscription {
                  ...SubscriptionDetail
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class SubscriptionsQueryBinder < QueryBinder
      # Updates a subscription
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param id [String] The ID of the subscription.
      # @param last_processed [Time] The time a report was last processed.
      # @param detail_fragment [String] GraphQL detail fragment for the model
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def update(**kwargs)
        Response.new Client::Subscriptions::UpdateSubscriptionMutation.execute(client: client, **kwargs)
      end
    end
  end
end
