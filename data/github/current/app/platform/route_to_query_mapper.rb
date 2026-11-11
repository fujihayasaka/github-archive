# typed: true
# frozen_string_literal: true

module Platform
  # Maps routes to used query ids
  class RouteToQueryMapper
    def initialize(backend:)
      @backend = backend
    end

    def fetch(route)
      backend.fetch(route)
    end

    def fetch_variables(query_id)
      backend.fetch_variables(query_id)
    end

    def get_matching_url_pattern(route)
      backend.get_matching_url_pattern(route)
    end

    private

    attr_reader :backend
  end
end
