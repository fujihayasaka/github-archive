# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Scorecards
      # Update score for a given service and scorecard.
      module UpdateScorecardScoreMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecards.update_score"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "actionItems" => "[ActionItemInput!]",
          "notes" => "String!",
          "objectiveName" => "String!",
          "references" => "[RequirementScoreReferenceInput!]",
          "requirementName" => "String!",
          "score" => "Int!",
          "scorecardName" => "String!",
          "serviceName" => "String!",
        }

        # Update score for a given service and scorecard.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param detail_fragment [String] GraphQL detail fragment defining RequirementScoreDetail (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param actionItems [Array] Action items to address for this requirement
        # @param notes [String] Any notes to go along with the score.
        # @param objective_name [String] Name of the objective
        # @param references [Array] References to address for this score
        # @param requirement_name [String] Name of the requirement
        # @param score [Integer] Numerical score
        # @param scorecard_name [String] Name of the scorecard
        # @param service_name [String] Name of the service
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: ScorecardsQueryBinder::REQUIREMENT_SCORE_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          variables["score"] = variables["score"].to_i
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "updateScorecardScore")
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        # @param detail_fragment [String] GraphQL detail fragment defining RequirementScoreDetail (optional)
        #
        # @return [String] The mutation query
        def self.build_query(variables, detail_fragment: ScorecardsQueryBinder::REQUIREMENT_SCORE_DETAIL_FRAGMENT)
          <<~GRAPHQL
            mutation updateScorecardScore#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              updateScorecardScore(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                requirementScore {
                  ...RequirementScoreDetail
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class ScorecardsQueryBinder < QueryBinder
      # Update score for a given service and scorecard.
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param actionItems [Array] Action items to address for this requirement
      # @param notes [String] Any notes to go along with the score.
      # @param objective_name [String] Name of the objective
      # @param references [Array] References to address for this score
      # @param requirement_name [String] Name of the requirement
      # @param score [Integer] Numerical score
      # @param scorecard_name [String] Name of the scorecard
      # @param service_name [String] Name of the service
      # @param context [Hash] Additional headers to add to the request (optional)
      # @param detail_fragment [String] GraphQL detail fragment defining RequirementScoreDetail (optional)
      #
      # @return [Response]
      def update_score(**kwargs)
        Response.new Client::Scorecards::UpdateScorecardScoreMutation.execute(client: client, **kwargs)
      end
    end
  end
end
