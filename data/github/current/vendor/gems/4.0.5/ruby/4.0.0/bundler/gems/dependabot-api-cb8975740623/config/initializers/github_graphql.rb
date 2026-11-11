# frozen_string_literal: true

require "graphql/client"
require "graphql/client/http"

module GitHubGraphQL
  class MissingAccount < StandardError; end
  class MisconfiguredTenant < StandardError; end
  class ServerError < StandardError; end
  class RateLimited < StandardError; end

  class UnauthorizedError < StandardError; end

  module Client
    DEFAULT_ENDPOINT = Dependabot::Application.target_github_graphql_endpoint
    ACCESS_TOKEN = Prius.get(:dependabot_service_token)

    # This schema is available from our codespace-compose env via CURL:
    # curl -H "Authorization: bearer $TOKEN" \
    #      -H "GraphQL-Schema: internal" \
    #      http://github.localhost:3000/api/graphql | jq .
    #
    # The $TOKEN does not need any additional scopes.
    SCHEMA_PATH = "static/github_graphql_schema.json"
    SCHEMA = Rails.root.join(SCHEMA_PATH).to_s

    def self.build(endpoint: DEFAULT_ENDPOINT) # rubocop:disable Metrics/MethodLength
      http_adapter = GraphQL::Client::HTTP.new(endpoint) do
        def headers(context) # rubocop:disable Lint/NestedMethodDefinition
          raise MissingAccount unless context[:account]

          account = context[:account]
          {
            "Authorization" => "Bearer #{access_token(account)}",
            "Accept" => context[:accept_header],
            "GraphQL-Schema" => "internal",
            "GitHub-Internal-GraphQL-Token" => ACCESS_TOKEN,
            "X-GitHub-Tenant" => tenant_header_value(account),
          }.compact
        end

        def tenant_header_value(account) # rubocop:disable Lint/NestedMethodDefinition
          return unless Dependabot.proxima?
          raise MisconfiguredTenant if account.tenant.slug.blank?

          account.tenant.slug
        end

        def access_token(account) # rubocop:disable Lint/NestedMethodDefinition
          GitHubHelpers.access_token_for(account: account)
        end
      end

      GraphQL::Client.new(schema: SCHEMA, execute: http_adapter).tap do |client|
        client.allow_dynamic_queries = true
      end
    end
  end

  def self.client
    @client ||= Client.build
  end
end
