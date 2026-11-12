# typed: true
# frozen_string_literal: true

module ServiceCatalog
  class Client
    module Services
      # List all support levels for a service.
      module ListSupportLevelsQuery
        # The instrumentation key for this query used by ActiveSupport::Notifications.
        INSTRUMENTATION_KEY = "service_catalog_client.services.support_levels"

        # GraphQL types for the known GraphQL arguments
        VARIABLE_GRAPHQL_TYPES = {
          "after" => "String",
          "before" => "String",
          "first" => "Int",
          "last" => "Int",
          "offset" => "Int",
          "serviceName" => "String!",
        }

        # Execute the List Service Support Levels query to list all support levels for a service.
        #
        # @param client [ServiceCatalog::Client] The ServiceCatalog::Client
        # @param context [Hash] Additional headers to add to the request (optional)
        # @param detail_fragment [String] (optional) A GraphQL fragment defining 'SupportLevelDetail' to fetch the fields desired
        # @param service_name [String] The name of the service whose support levels you're requesting (exact)
        #
        # @return Hash with "errors" and "data" keys.
        def self.execute(client:, context: {}, detail_fragment: ServicesQueryBinder::SUPPORT_LEVEL_DETAIL_FRAGMENT, **kwargs)
          variables = GraphqlQuerySemantics.kwargs_to_graphql_variables(kwargs)
          variables["after"] ||= nil
          query = build_query(variables, detail_fragment: detail_fragment)

          data = {"data" => {"supportLevels" => []}, "errors" => []}
          ActiveSupport::Notifications.instrument(INSTRUMENTATION_KEY) do
            loop do
              response = client.query_with_retries(query: query, variables: variables, context: context)
              if response["errors"]
                data["errors"].concat(response["errors"])
                break
              end
              if response["data"]["service"].nil?
                data["errors"].push("The service: #{variables["serviceName"]} could not be found.")
                break
              end
              Array(response.dig("data", "service", "supportLevels", "edges")).each do |edge|
                data["data"]["supportLevels"] << edge["node"]
              end
              break if data["data"]["supportLevels"].size >= response.dig("data", "service", "supportLevels", "totalCount")
              variables["after"] = response.dig("data", "service", "supportLevels", "edges").last["cursor"]
            end
          end

          data
        end

        # Build the query to list support levels with pagination.
        #
        # @param variables [Hash] GraphQL variables
        # @param detail_fragment [String] (optional) A GraphQL fragment defining 'SupportLevelDetail' to fetch the fields desired
        #
        # @return [String] the GraphQL query
        def self.build_query(variables, detail_fragment: ServicesQueryBinder::SUPPORT_LEVEL_DETAIL_FRAGMENT)
          support_levels_variables = variables.select { |k, _| k != "serviceName" }
          <<~GRAPHQL
            query listSupportLevels#{GraphqlQuerySemantics.graphql_variable_declaration(variables, variable_types: VARIABLE_GRAPHQL_TYPES, include_parens: true)} {
              service(name: $serviceName) {
                supportLevels#{GraphqlQuerySemantics.graphql_variable_passing(support_levels_variables, include_parens: true)} {
                  totalCount
                  edges {
                    cursor
                    node {
                      ...SupportLevelDetail
                    }
                  }
                }
              }
            }
            #{detail_fragment}
          GRAPHQL
        end
      end
    end

    class ServicesQueryBinder < QueryBinder
      # List all Support Levels for a given Service.
      #
      # @param service_name [String] The name of the service (exact)
      # @param context [Hash] (optional) Optional headers to add to the request
      # @param detail_fragment [String] (optional) A GraphQL fragment defining 'SupportLevelDetail' to fetch the fields desired
      #
      # @return [Response] All support levels for the service
      def support_levels(service_name:, detail_fragment: SUPPORT_LEVEL_DETAIL_FRAGMENT, context: {})
        Response.new Client::Services::ListSupportLevelsQuery.execute(client: client, service_name: service_name, detail_fragment: detail_fragment, context: context)
      end
    end
  end
end
