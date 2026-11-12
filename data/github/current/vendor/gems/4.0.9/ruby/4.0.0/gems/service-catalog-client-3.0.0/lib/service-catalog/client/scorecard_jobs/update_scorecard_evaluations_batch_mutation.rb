# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module ScorecardJobs
      # Update a scorecard evaluation for a service.
      module UpdateScorecardEvaluationsBatchMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecard_jobs.batch_update_scorecard_evaluations"

        # Submit batch scorecard evaluation updates.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param detail_fragment [String] GraphQL detail fragment defining `RequirementScoreDetail` (optional)
        # @param evaluations [Array] Array of Hash evaluations containing keys:
        #          - scorecard_name [String] The name of the scorecard
        #          - service_name [String] The name of the service that was evaluated
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: ScorecardJobsQueryBinder::SCORECARD_JOB_DETAIL_FRAGMENT, **kwargs)
          variables = prepare_batch_input(**kwargs)
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"batch" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY, batch_size: variables.size) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["batch"] = response.dig("data")
          end

          data
        end

        # Build query for updating a scoreccard score given the input variables (in GraphQL form).
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        # @param detail_fragment [String] GraphQL detail fragment defining `RequirementScoreDetail` (optional)
        #
        # @return [String] The mutation query
        def self.build_query(variables, detail_fragment: ScorecardJobsQueryBinder::SCORECARD_JOB_DETAIL_FRAGMENT, **kwargs)
          operations = variables.each_with_object([]) do |(k, _), ops|
            ops << <<~GRAPHQL
              #{k}: updateScorecardEvaluation(input: $#{k}) {
                clientMutationId
                scorecardJob {
                  ...ScorecardJobDetail
                }
              }
            GRAPHQL
          end

          variable_types = variables.each_with_object({}) { |(k, v), types| types[k] = "UpdateScorecardEvaluationInput!" }
          <<~GRAPHQL
            mutation updateScorecardEvaluationBatch(#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: variable_types)}){
              #{operations.join("\n")}
            }
            #{detail_fragment}
          GRAPHQL
        end

        def self.prepare_batch_input(evaluations:)
          evaluations.each.with_index.with_object({}) do |(score, index), vars|
            key = "operation#{index.to_s.rjust(4, "0")}"
            vars[key] = score.transform_keys { |k| ActiveSupport::Inflector.camelize(k, false) }
            vars[key]["clientMutationId"] = key
          end
        end
      end
    end


    class ScorecardJobsQueryBinder < QueryBinder
      # Submit batch scorecard evaluation updates.
      #
      # @param context [Hash] Additional headers to add to the request (optional)
      # @param detail_fragment [String] GraphQL detail fragment defining `RequirementScoreDetail` (optional)
      # @param evaluations [Array] Array of Hash evaluations containing keys:
      #          - scorecard_name [String] The name of the scorecard
      #          - service_name [String] The name of the service to score (exact)
      #
      # @return [Response]
      def batch_update_scorecard_evaluations(**kwargs)
        Response.new Client::ScorecardJobs::UpdateScorecardEvaluationsBatchMutation.execute(client: client, **kwargs)
      end
    end
  end
end
