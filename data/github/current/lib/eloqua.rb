# typed: true
# frozen_string_literal: true

module Eloqua
  autoload :HttpClient, "eloqua/http_client"
  autoload :RestApiClient, "eloqua/rest_api_client"

  class << self # rubocop:disable Style/ClassMethodsDefinitions
    def cache_provider=(cache_provider)
      @cache_provider = cache_provider
    end

    def cache_provider
      @cache_provider || NullCache.new
    end

    class NullCache
      def fetch(*_args)
        yield
      end
    end
  end
end
