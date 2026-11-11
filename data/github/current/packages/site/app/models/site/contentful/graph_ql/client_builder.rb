# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module GraphQL
      class ClientBuilder
        include GitHub::Memoizer

        SPACE_CONFIGS = T.let({
          marketing: {
            space_id: GitHub.contentful_marketing_space_id,
            environment: GitHub.contentful_marketing_environment,
            delivery_token: GitHub.contentful_marketing_delivery_token,
            preview_token: GitHub.contentful_marketing_preview_token,
            schema_location: "packages/site/config/generated_graphql_schemas/marketing.json",
          },
        }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

        sig { params(space: Symbol, preview: T::Boolean).void }
        def initialize(space:, preview: false)
          @space = space
          @preview = preview
        end

        sig { returns(T.any(::GraphQL::Client, NullClient)) }
        def build
          ::GraphQL::Client.new(schema: load_schema, execute: http)
        rescue StandardError => e
          Failbot.report(e, "Failed to build GraphQL client for Contentful space #{@space}")
          NullClient.new
        end

        # Utility method to dump the schema to a file. Returns the schema file path for convenience.
        sig { returns(String) }
        def dump_schema
          ::GraphQL::Client.dump_schema(http, schema_location)
          schema_location
        end

        private

        sig { returns(T.untyped) }
        memoize def http
          ::GraphQL::Client::HTTP.new("https://graphql.contentful.com/content/v1/spaces/#{space_id}/environments/#{environment}") do
            sig { params(_context: T.untyped).returns(T::Hash[Symbol, String]) }
            def headers(_context)
              # Optionally set any HTTP headers
              { "Authorization": "Bearer #{GitHub.contentful_marketing_delivery_token}" }
            end
          end
        end

        sig { returns(T.untyped) }
        def load_schema
          ::GraphQL::Client.load_schema(schema_location)
        end

        sig { returns(String) }
        def space_id
          SPACE_CONFIGS.dig(@space, :space_id) || ""
        end

        sig { returns(String) }
        def environment
          SPACE_CONFIGS.dig(@space, :environment) || ""
        end

        sig { returns(String) }
        def access_token
          token_key = @preview ? :preview_token : :delivery_token
          SPACE_CONFIGS.dig(@space, token_key) || ""
        end

        sig { returns(String) }
        def schema_location
          SPACE_CONFIGS.dig(@space, :schema_location) || ""
        end
      end
    end
  end
end
