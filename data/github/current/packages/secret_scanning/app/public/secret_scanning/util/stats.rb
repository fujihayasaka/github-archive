# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class Stats
    # Emit a metric to keep track of graceful failures to be used in our availability monitors / SLOs
    # For example, a request that fails to load data from the back-end but displays a graceful error to the user would be tracked as a failure,
    # even though the response is not a 5xx
    sig { params(env: T::Hash[T.untyped, T.untyped]).void }
    def self.track_graceful_failure(env)
      tags = self.get_base_tags(env)

      GitHub.dogstats.increment(
        "github/secret_scanning.graceful_failure",
        tags: tags,
      )
    end

    sig { params(env: T::Hash[T.untyped, T.untyped]).returns(T::Array[String]) }
    private_class_method def self.get_base_tags(env)
      controller = GitHub::TaggingHelper.controller(env)

      [
        "#{GitHub::TaggingHelper::CONTROLLER_TAG}:#{controller}",
        "#{GitHub::TaggingHelper::ACTION_TAG}:#{GitHub::TaggingHelper.action(env)}",
        "#{GitHub::TaggingHelper::METHOD_TAG}:#{GitHub::TaggingHelper.request_method(env)}",
        "#{GitHub::TaggingHelper::CATALOG_SERVICE_TAG}:github/secret-scanning",
        "#{GitHub::TaggingHelper::CATEGORY_TAG}:#{GitHub::TaggingHelper.category(env)}",
        "#{GitHub::TaggingHelper::INTERNAL_API_TAG}:#{GitHub::TaggingHelper.internal_api?(env)}",
        "#{GitHub::TaggingHelper::GRAPHQL_API_TAG}:#{GitHub::TaggingHelper.graphql_api_request?(controller)}",
      ]
    end
  end
end
