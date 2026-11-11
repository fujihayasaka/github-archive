# frozen_string_literal: true

module GitHub
  class RESTClient < ::Octokit::Client
    module EtagCache
      def using_etag_cache
        return self if middleware.handlers.include?(Faraday::EtagCache)

        middleware.insert(0, Faraday::EtagCache, cache: Rails.cache)

        # The agent needs to be reset after changing the middleware stack
        @agent = nil

        self
      end
    end
  end
end
