# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Scorecards
      # Scorecard score trends over time
      module ScorecardTrendReportQuery
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecards.trend_report"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "scorecardName" => "String!",
          "endDate" => "ISO8601DateTime",
          "filterSelection" => "ServiceFilterSelectionInput",
          "groupBy" => "ScorecardTrendGroupByField",
          "numberOfPeriods" => "Int",
          "period" => "ScorecardTrendPeriod",
          "after" => "String",
          "before" => "String",
          "first" => "Int",
          "last" => "Int",
        }

        # Scorecard score trends over time
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param end_date [Time] The date of the last data point for this report
        # @param filter_selection [ServiceFilterSelectionInput] A selection for filtering services.
        # @param group_by [String] Service field to group by (default: "exec_sponsor")
        # @param number_of_periods [Integer] Number of periods to report (default: 3)
        # @param period [ScorecardTrendPeriod] The period of time to aggregate over (default: "MONTHLY")
        # @param scorecard_name [String] The name of the scorecard to report
        #
        # @return [Hash]
        def self.execute(client:, context: {}, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          variables["after"] ||= nil
          query = build_query(variables)

          data = {"data" => {"scorecard" => nil}, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            loop do
              response = client.query_with_retries(query: query, variables: variables, context: context)
              if response["errors"]
                data["errors"].concat(response["errors"])
                return data
              end

              # Preserve original edges so we can return them the way we want.
              trend_edges = Array(response.dig("data", "scorecard", "trendReport", "trends", "edges"))

              # Load up the metadata, and clear the edges.
              if data.dig("data", "scorecard").nil?
                data["data"]["scorecard"] = response.dig("data", "scorecard")
                data["data"]["scorecard"]["trendReport"]["trends"]["edges"] = []
              end

              # Add any edges collapsed down so there's no "node" level.
              trend_edges.each do |edge|
                data["data"]["scorecard"]["trendReport"]["trends"]["edges"] << edge["node"]
              end

              break if data.dig("data", "scorecard", "trendReport", "trends", "edges").size >= response.dig("data", "scorecard", "trendReport", "trends", "totalCount")
              variables["after"] = trend_edges.last["cursor"]
            end
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        #
        # @return [String] The mutation query
        def self.build_query(variables, **kwargs)
          trendReportVariables = variables.select { |k, _| k != "scorecardName" && k != "after" }
          trendsVariables = variables.select { |k, _| k == "after" || k == "before" || k == "first" || k == "last" }
          <<~GRAPHQL
            query trendReport#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              scorecard(name: $scorecardName) {
                trendReport#{GraphqlQuerySemantics.graphql_variable_passing(trendReportVariables, include_parens: true)} {
                  reportName
                  groupByTitle
                  groupByField
                  trendPeriod
                  trends#{GraphqlQuerySemantics.graphql_variable_passing(trendsVariables, include_parens: true)} {
                    totalCount
                    edges {
                      cursor
                      node {
                        value
                        periods {
                          name
                          currentPoints
                          maxPoints
                          passingThreshold
                          servicesMet
                          servicesTotal
                          actionItemCount
                        }
                      }
                    }
                  }
                }
              }
            }
          GRAPHQL
        end
      end
    end

    class ScorecardsQueryBinder < QueryBinder
      # Scorecard score trends over time
      #
      # @param end_date [Time] The date of the last data point for this report
      # @param filter_selection [ServiceFilterSelectionInput] A selection for filtering services.
      # @param group_by [String] Service field to group by
      # @param number_of_periods [Integer] Number of periods to report
      # @param period [ScorecardTrendPeriod] The period of time to aggregate over
      # @param scorecard_name [String] The name of the scorecard to report
      # @param detail_fragment [String] GraphQL detail fragment for the model
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def trend_report(**kwargs)
        Response.new Client::Scorecards::ScorecardTrendReportQuery.execute(client: client, **kwargs)
      end
    end
  end
end
