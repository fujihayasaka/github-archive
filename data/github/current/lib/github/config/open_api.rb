# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module OpenApi
      def default_openapi_release
        return @default_openapi_release if defined?(@default_openapi_release)
        @default_openapi_release = "api.github.com"
      end

      def enterprise_test_openapi_release
        return @enterprise_test_openapi_release if defined?(@enterprise_test_openapi_release)

        @enterprise_test_openapi_release = "ghes-99.99"
      end

      def enterprise_openapi_release
        return @enterprise_openapi_release if defined?(@enterprise_openapi_release)
        @enterprise_openapi_release = "ghes-#{GitHub.version_number}"
      end

      # Public: Which OpenAPI release name to use.
      #
      # Returns a boolean.
      def openapi_release
        return @openapi_release if defined?(@openapi_release)

        raise "You haven't specified a GitHub.openapi_release. Please do so in a config/environments file."
      end
      attr_writer :openapi_release

      def openapi_include_webhooks
        return @openapi_include_webhooks if defined?(@openapi_include_webhooks)
        @openapi_include_webhooks = false
      end
      alias openapi_include_webhooks? openapi_include_webhooks
      attr_writer :openapi_include_webhooks

      def openapi_include_test_fixtures
        return @openapi_include_test_fixtures if defined?(@openapi_include_test_fixtures)
        @openapi_include_test_fixtures = false
      end
      alias openapi_include_test_fixtures? openapi_include_test_fixtures
      attr_writer :openapi_include_test_fixtures

      def openapi_merge_ghec_operations
        return @openapi_merge_ghec_operations if defined?(@openapi_merge_ghec_operations)
        @openapi_merge_ghec_operations = false
      end
      alias openapi_merge_ghec_operations? openapi_merge_ghec_operations
      attr_writer :openapi_merge_ghec_operations
    end
  end

  extend Config::OpenApi
end
