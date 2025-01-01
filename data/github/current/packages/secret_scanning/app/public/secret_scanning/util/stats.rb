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

    sig { params(num_bytes: Integer).returns(String) }
    def self.get_stat_size_bucket_for_bytes(num_bytes)
      return "0-1KB" if num_bytes <= 1024
      return "1KB-1MB" if num_bytes <= 1024 * 1024
      return "1MB-5MB" if num_bytes <= 1024 * 1024 * 5
      return "5MB-10MB" if num_bytes <= 1024 * 1024 * 10
      return "10MB-50MB" if num_bytes <= 1024 * 1024 * 50
      return "50MB-100MB" if num_bytes <= 1024 * 1024 * 100
      "100MBplus"
    end

    sig { params(count: Integer).returns(String) }
    def self.get_stat_size_bucket_for_count(count)
      return "0-10" if count <= 10
      return "10-100" if count <= 100
      return "100-1000" if count <= 1000
      return "1000-10000" if count <= 10000
      return "10000-100000" if count <= 100000
      "100000plus"
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
