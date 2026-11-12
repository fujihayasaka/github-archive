# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Scorecards
      # Update or create a scorecard.
      module UpdateScorecardMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecards.update_scorecard"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "scorecard" => "ScorecardInput!",
        }

        # Update or create a scorecard.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param scorecard [Hash] Scorecard data, fields include:
        #     - aqueduct_queue [String] Name of the Aqueduct queue in which to send scorecard update requests.
        #     - description [String] A description of the scorecard.
        #     - editors [Array] User logins who can submit scores for the scorecard.
        #     - is_fundamental [Boolean] Whether the scorecard is in scope for Fundamentals (default: false)
        #     - maintainer [String] A single individual ultimately responsible for the scorecard.
        #     - milestones [Array] Milestones for the scorecard.
        #     - name [String] The scorecard name.
        #     - objectives [Array] Objectives for the scorecard.
        #     - passing_threshold [Integer] Passing threshold in raw points.
        #     - scoring_code_url [String] A URL to the code used to generate scores for the scorecard.
        #     - slack [String] Name of slack room for support.
        #     - team [String] A group that shares the ownership responsibilities with the maintainer.
        # @param detail_fragment [String] GraphQL detail fragment for the model
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: ScorecardsQueryBinder::SCORECARD_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "updateScorecard")
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        #
        # @return [String] The mutation query
        def self.build_query(variables, detail_fragment: ScorecardsQueryBinder::SCORECARD_DETAIL_FRAGMENT, **kwargs)
          <<~GRAPHQL
            mutation updateScorecard#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              updateScorecard(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                scorecard {
                  ...ScorecardDetail
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class ScorecardsQueryBinder < QueryBinder
      # Update or create a scorecard.
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param scorecard [Hash] Scorecard data, fields include:
      #     - aqueduct_queue [String] Name of the Aqueduct queue in which to send scorecard update requests.
      #     - description [String] A description of the scorecard.
      #     - editors [Array] User logins who can submit scores for the scorecard.
      #     - is_fundamental [Boolean] Whether the scorecard is in scope for Fundamentals (default: false)
      #     - maintainer [String] A single individual ultimately responsible for the scorecard.
      #     - milestones [Array] Milestones for the scorecard.
      #     - name [String] The scorecard name.
      #     - objectives [Array] Objectives for the scorecard.
      #     - passing_threshold [Integer] Passing threshold in raw points.
      #     - slack [String] Name of slack room for support.
      #     - team [String] A group that shares the ownership responsibilities with the maintainer.
      # @param detail_fragment [String] GraphQL detail fragment for the model
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def update(**kwargs)
        Response.new Client::Scorecards::UpdateScorecardMutation.execute(client: client, **kwargs)
      end
    end
  end
end
