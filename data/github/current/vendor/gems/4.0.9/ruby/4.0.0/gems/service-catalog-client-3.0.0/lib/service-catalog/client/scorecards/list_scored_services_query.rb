# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Scorecards
      # A list of services with scores for this scorecard
      module ListScoredServicesQuery
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecards.scored_services"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "after" => "String",
          "before" => "String",
          "filterSelection" => "ServiceFilterSelectionInput",
          "first" => "Int",
          "last" => "Int",
          "offset" => "Int",
          "scorecardName" => "String!",
        }

        # A list of services with scores for this scorecard
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param after [String] Returns the elements in the list that come after the specified cursor.
        # @param before [String] Returns the elements in the list that come before the specified cursor.
        # @param filter_selection [ServiceFilterSelectionInput] A selection for filtering services.
        # @param first [Integer] Returns the first _n_ elements from the list.
        # @param last [Integer] Returns the last _n_ elements from the list.
        # @param offset [Integer] Offset the services returned by the input number
        # @param scorecard_name [String] Name of the scorecard whose services to list
        # @param service_detail_fragment [String] GraphQL detail fragment defining ServiceDetail
        #
        # @return [Hash]
        def self.execute(client:, context: {}, service_detail_fragment: ServicesQueryBinder::SERVICE_MINIMAL_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          variables["after"] ||= nil
          variables["filterSelection"] ||= {"query" => ""}
          query = build_query(variables, service_detail_fragment: service_detail_fragment)

          data = {"data" => {"services" => []}, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            loop do
              response = client.query_with_retries(query: query, variables: variables, context: context)
              if response["errors"]
                data["errors"].concat(response["errors"])
                break
              end
              response.dig("data", "scorecard", "services", "edges").each do |edge|
                data["data"]["services"] << edge["node"]
              end
              break unless response.dig("data", "scorecard", "services", "pageInfo", "hasNextPage")
              variables["after"] = response.dig("data", "scorecard", "services", "pageInfo", "endCursor")
            end
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        # @param service_detail_fragment [String] GraphQL detail fragment defining ServiceDetail
        #
        # @return [String] The mutation query
        def self.build_query(variables, service_detail_fragment: ServicesQueryBinder::SERVICE_MINIMAL_DETAIL_FRAGMENT, **kwargs)
          services_variables = variables.reject { |k, _| k == "scorecardName" }
          <<~GRAPHQL
            query listScorecardScoredServices#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              scorecard(name: $scorecardName) {
                services#{GraphqlQuerySemantics.graphql_variable_passing(services_variables, include_parens: true)} {
                  totalCount
                  pageInfo {
                    hasNextPage
                    endCursor
                  }
                  edges {
                    cursor
                    node {
                      ...ServiceDetail
                      scorecardSummaries(scorecard: $scorecardName, first: 1) {
                        nodes {
                          date
                          score
                          maxScore
                        }
                      }
                    }
                  }
                }
              }
            }
            #{service_detail_fragment}
          GRAPHQL
        end
      end
    end

    class ScorecardsQueryBinder < QueryBinder
      # A list of services with scores for this scorecard
      #
      # @param after [String] Returns the elements in the list that come after the specified cursor.
      # @param before [String] Returns the elements in the list that come before the specified cursor.
      # @param filter_selection [ServiceFilterSelectionInput] A selection for filtering services.
      # @param first [Integer] Returns the first _n_ elements from the list.
      # @param last [Integer] Returns the last _n_ elements from the list.
      # @param offset [Integer] Offset the services returned by the input number
      # @param scorecard_name [String] Name of the scorecard whose services to list
      # @param service_detail_fragment [String] GraphQL detail fragment defining ServiceDetail
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def list_scored_services(**kwargs)
        Response.new Client::Scorecards::ListScoredServicesQuery.execute(client: client, **kwargs)
      end
    end
  end
end
