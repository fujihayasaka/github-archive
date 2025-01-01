# typed: true
# frozen_string_literal: true

module Insights
  class QueryComponent < ApplicationComponent
    include UrlHelpers
    include InsightsHelper

    API_ROUTES = {
      "insights" => "sql/api",
      "datadot" => "data_warehouse/api"
    }
    PLACEHOLDER_HEIGHT = 300
    attr_reader :query, :api_route

    def initialize(query, employee: false, target: nil, data_context: {})
      # Decoding the HTML to get the plain SQL query text
      @query = CGI.unescapeHTML(query)
      @employee = employee
      @data_context = data_context
      @api_route = API_ROUTES[target] || API_ROUTES["insights"]
    end

    def api_token_path
      insights_auth_and_config_insights_path(repository_id: repository_id, organization_id: organization_id)
    end

    def insights_api_path
      "#{insights_api_server_endpoint}/#{api_route}"
    end

    def employee?
      @employee
    end

    def insights_api_server_endpoint
      if env_directive == "staging" && employee?
        # note: using the staging environment requires being connected to the GitHub production vpn
        return GitHub.insights_staging_api_server_endpoint
      end

      GitHub.insights_api_server_endpoint
    end

    memoize def env_directive
      query.match(/--\s*env=(?<env>[^\s]+)/) { |matchdata| matchdata[:env]&.downcase }
    end

    def repository_id
      @data_context.dig("github", "repository", "id")
    end

    def organization_id
      @data_context.dig("github", "organization", "id")
    end
  end
end
