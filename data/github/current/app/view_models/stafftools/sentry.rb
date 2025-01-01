# typed: true
# frozen_string_literal: true

module Stafftools
  module Sentry
    DOTCOM_PROJECT_ID = 1885898
    GITHUB_USER_PROJECT_ID = 1886027

    # Generates a Sentry URL for specific projects and a query.
    #
    # Example URL: https://sentry.io/organizations/github/issues/?project=1&project=2&query=repo_id:1234
    #
    #
    # project_ids - Array of Integer, representing the IDs of projects to search.
    # query - String representing the query.
    #
    # Returns String.
    def sentry_query_link(project_ids = [], query)
      projects = project_ids.map { |id| "project=#{id}" }.join("&")
      query = { query: query }.to_query
      query = "&#{query}" if project_ids.any?
      "https://sentry.io/organizations/github/issues/?#{projects}#{query}"
    end
  end
end
