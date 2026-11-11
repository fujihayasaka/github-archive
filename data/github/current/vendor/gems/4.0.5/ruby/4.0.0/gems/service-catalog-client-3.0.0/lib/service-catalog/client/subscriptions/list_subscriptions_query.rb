# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Subscriptions
      # A list of subscriptions
      module ListSubscriptionsQuery
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.subscriptions.subscriptions"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "after" => "String",
          "before" => "String",
          "destination" => "String",
          "destinationKind" => "SubscriptionDestinationKind",
          "kind" => "SubscriptionKind",
          "first" => "Int",
          "last" => "Int",
          "offset" => "Int",
        }

        # A list of subscriptions
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param after [String] Returns the elements in the list that come after the specified cursor.
        # @param before [String] Returns the elements in the list that come before the specified cursor.
        # @param destination [String] Filter by the report destination.
        # @param destination_kind [SubscriptionDestinationKind] Filter by the report destination kind. Possible values are:
        #     - slack
        # @param kind [SubscriptionKind] Filter by the subscription kind. Possible values are:
        #     - scorecard
        #     - slo
        # @param first [Integer] Returns the first _n_ elements from the list.
        # @param last [Integer] Returns the last _n_ elements from the list.
        # @param offset [Integer] The number of records to skip when returning results. Useful for pagination.
        # @param detail_fragment [String] GraphQL detail fragment for the model
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: SubscriptionsQueryBinder::SUBSCRIPTION_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          variables["after"] ||= nil
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"data" => {"subscriptions" => []}, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            loop do
              response = client.query_with_retries(query: query, variables: variables, context: context)
              if response["errors"]
                data["errors"].concat(response["errors"])
                break
              end
              response["data"]["subscriptions"]["edges"].each do |edge|
                data["data"]["subscriptions"] << edge["node"]
              end
              break unless response["data"]["subscriptions"]["pageInfo"]["hasNextPage"]
              variables["after"] = response["data"]["subscriptions"]["pageInfo"]["endCursor"]
            end
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
            query listSubscriptions#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              subscriptions#{GraphqlQuerySemantics.graphql_variable_passing(variables, include_parens: true)} {
                totalCount
                pageInfo {
                  hasNextPage
                  endCursor
                }
                edges {
                  node {
                    ...SubscriptionDetail
                  }
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class SubscriptionsQueryBinder < QueryBinder
      # A list of subscriptions
      #
      # @param after [String] Returns the elements in the list that come after the specified cursor.
      # @param before [String] Returns the elements in the list that come before the specified cursor.
      # @param destination [String] Filter by the report destination.
      # @param destination_kind [SubscriptionDestinationKind] Filter by the report destination kind. Possible values are:
      #     - slack
        # @param kind [SubscriptionKind] Filter by the subscription kind. Possible values are:
        #     - scorecard
        #     - slo
      # @param first [Integer] Returns the first _n_ elements from the list.
      # @param last [Integer] Returns the last _n_ elements from the list.
      # @param offset [Integer] The number of records to skip when returning results. Useful for pagination.
      # @param detail_fragment [String] GraphQL detail fragment for the model
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def list(**kwargs)
        Response.new Client::Subscriptions::ListSubscriptionsQuery.execute(client: client, **kwargs)
      end
    end
  end
end
