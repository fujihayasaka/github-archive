# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module ScorecardJobs
      # Creates a scorecard job
      module CreateScorecardJobMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.scorecard_jobs.create_scorecard_job"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "scorecardName" => "String!",
          "serviceName" => "String!",
        }

        # Creates a scorecard job
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param scorecard_name [String] The name of the scorecard.
        # @param service_name [String] The name of the service.
        # @param detail_fragment [String] GraphQL detail fragment for the model
        #
        # @return [Hash]
        def self.execute(client:, context: {}, detail_fragment: ScorecardJobsQueryBinder::SCORECARD_JOB_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "createScorecardJob")
          end

          data
        end

        # Build query for this query.
        #
        # @param variables [Hash] Input variables in GraphQL variable format as keys.
        #
        # @return [String] The mutation query
        def self.build_query(variables, detail_fragment: ScorecardJobsQueryBinder::SCORECARD_JOB_DETAIL_FRAGMENT, **kwargs)
          <<~GRAPHQL
            mutation createScorecardJob#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              createScorecardJob(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                scorecardJob {
                  ...ScorecardJobDetail
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class ScorecardJobsQueryBinder < QueryBinder
      # Creates a scorecard job
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param scorecard_name [String] The name of the scorecard.
      # @param service_name [String] The name of the service.
      # @param detail_fragment [String] GraphQL detail fragment for the model
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def create(**kwargs)
        Response.new Client::ScorecardJobs::CreateScorecardJobMutation.execute(client: client, **kwargs)
      end
    end
  end
end
