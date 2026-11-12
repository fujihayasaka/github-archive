# typed: false
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Services
      # Validate the service contains the necessary ownership information to deploy.
      module ValidateServiceForDeploymentMutation
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.services.validate_service_for_deployment"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "clientMutationId" => "String",
          "owner" => "String!",
          "repo" => "String!",
          "sha" => "String",
          "writeStatus" => "Boolean",
        }

        # Validate the service contains the necessary ownership information to deploy.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
        # @param owner [String] The repository owner
        # @param repo [String] The repository name
        # @param sha [String] The repository commit SHA to apply the status to
        # @param write_status [Boolean] Whether to write the CI status
        #
        # @return [Hash]
        def self.execute(client:, context: {}, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          query = build_query(variables)

          data = {"mutation" => nil, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            response = client.query_with_retries(query: query, variables: variables, context: context)
            data["errors"] = response["errors"] if response["errors"]
            data["mutation"] = response.dig("data", "validateServiceForDeployment")
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
            mutation validateServiceForDeployment#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              validateServiceForDeployment(input: { #{GraphqlQuerySemantics.graphql_variable_passing(variables)} }) {
                clientMutationId
                checks {
                  nodes {
                    name
                    requirement
                    details
                    result
                  }
                }
              }
            }
          GRAPHQL
        end
      end
    end

    class ServicesQueryBinder < QueryBinder
      # Validate the service contains the necessary ownership information to deploy.
      #
      # @param client_mutation_id [String] A unique identifier for the client performing the mutation.
      # @param owner [String] The repository owner
      # @param repo [String] The repository name
      # @param sha [String] The repository commit SHA to apply the status to
      # @param write_status [Boolean] Whether to write the CI status
      # @param context [Hash] Additional headers to add to the request (optional)
      #
      # @return [Response]
      def validate_service_for_deployment(**kwargs)
        Response.new Client::Services::ValidateServiceForDeploymentMutation.execute(client: client, **kwargs)
      end
    end
  end
end
