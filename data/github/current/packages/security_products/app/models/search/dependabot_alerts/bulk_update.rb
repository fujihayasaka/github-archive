# typed: strict
# frozen_string_literal: true

module Search::DependabotAlerts
  module BulkUpdate
    # This script is an all-inclusive update to Elasticsearch. It will
    # update a document's fields with the provided `params.field_updates` and
    # conditionally update the `search_index_updated_at` timestamp if the
    # `params.updated_at` timestamp is non-null and more recent.
    UPDATE_SCRIPT = T.let(<<~SOURCE.freeze, String)
      ctx._source.putAll(params.field_updates);
      if (params.updated_at == null) {
        return;
      }

      if (ctx._source.search_index_updated_at == null) {
        ctx._source.search_index_updated_at = params.updated_at;
      } else if (params.updated_at.compareTo(ctx._source.search_index_updated_at) > 0) {
        ctx._source.search_index_updated_at = params.updated_at;
      }
    SOURCE

    # Update `attributes` on all Dependabot alerts in Elasticsearch which match the provided
    # set of `filters` using Elasticsearch's update_by_query API.  Will also update each
    # document's `search_index_updated_at` to `updated_at` if and only if `updated_at`
    # is greater than the current `search_index_updated_at`.
    #
    # This function will not update the search_index_updated_at value for any RepositoryVulnerabilityAlert
    # records. Those updates are performed by calling
    # Search::DependabotAlerts::UpdateSearchIndexUpdatedAtJob.perform_later with the appropriate model.
    # The separation allows us to make a single update to alert documents in Elasticsearch which should
    # be more performant than batching updates in a Rails job, allowing us to minimize the time between
    # an update being made and the updated data being visible to users.
    sig do
      params(
        filters: T::Hash[Symbol, T.untyped],
        attributes: T::Hash[Symbol, T.untyped],
        updated_at: T.nilable(ActiveSupport::TimeWithZone),
        log_tags: T::Hash[T.any(String, Symbol), T.untyped],
        stats_tags: T::Array[String]
      ).returns(T.nilable(Elastomer::Interfaces::Api::UpdateByQuery::Response))
    end
    def self.update_all_matching(filters:, attributes:, updated_at:, log_tags: {}, stats_tags: [])
      return if filters.blank? || attributes.blank?

      client = self.new_client
      body = Elastomer::Interfaces::Api::UpdateByQuery::Request::Body.new(
        query: {
          bool: {
            filter: filters.map do |field, value|
              value.is_a?(Array) ? { terms: { field => value } } : { term: { field => value } }
            end
          }
        },
        script: Elastomer::Interfaces::Api::Request::Script.new(
          source: UPDATE_SCRIPT,
          params: {
            field_updates: attributes,
            updated_at: updated_at&.utc&.iso8601(3)
          }
        )
      )

      update_start_time = GitHub::Dogstats.monotonic_time
      response = client.update_by_query(body)
      duration = GitHub::Dogstats.duration(update_start_time)
      result = response.failures.present? ? "failed" : "success"

      # Metrics reporting to dogstats
      GitHub.dogstats.distribution("dependabot_alerts.search.bulk_update.time",
        duration,
        tags: [*stats_tags, "result:#{result}"]
      )
      GitHub.dogstats.distribution("dependabot_alerts.search.bulk_update.updated_count",
        response.updated,
        tags: [*stats_tags, "result:#{result}"]
      )

      if updated_at.present?
        # TODO: Enable lag calculation for cases when updated_at isn't provided
        # like repository transfers
        GitHub.dogstats.distribution("dependabot_alerts.search.bulk_update.lag",
          GitHub::Dogstats.duration(updated_at),
          tags: [*stats_tags, "result:#{result}"]
        )
      end

      # Logging and error reporting
      failures = response.failures&.map(&:reason)&.join(", ")
      log_tags = log_tags.merge(
        "code.namespace" => self.name,
        "code.function" => __method__,
        "result" => result,
        "updated_count" => response.updated,
        "duration" => duration,
      )
      if failures.present?
        err = StandardError.new("Failed to bulk update dependabot alerts search index")
        Failbot.report(err, log_tags.merge("failures" => failures))
        GitHub.logger.error("Bulk updated dependabot alerts search index", "failures" => failures, **log_tags)
      else
        GitHub.logger.info("Bulk updated dependabot alerts search index", **log_tags)
      end

      response
    rescue StandardError => e
      log_error(e, log_tags:, stats_tags:)
      raise
    end

    sig do
      params(
        error: StandardError,
        log_tags: T::Hash[T.any(String, Symbol), T.untyped],
        stats_tags: T::Array[String]
      ).void
    end
    def self.log_error(error, log_tags: {}, stats_tags: [])
      log_tags = log_tags.merge(
        "error.class" => error.class.name,
        "error.message" => error.message,
      )

      # get the calling method, accounting for sorbet-related stack frames
      calling_method = caller_locations(1)&.find { |call| !call.path&.include?("sorbet") }
      if calling_method
        calling_class_name, calling_method_name = T.must(calling_method.label).split(/[#\.]/)
        log_tags = log_tags.merge(
          "code.namespace" => calling_class_name,
          "code.function" => calling_method_name,
        )
      end

      Failbot.report(error, log_tags)
      GitHub.logger.error("Dependabot alerts search index bulk update error", **log_tags)

      GitHub.dogstats.increment("dependabot_alerts.search.bulk_update.error",
        tags: ["error:#{error.class.name}", *stats_tags]
      )
    end

    # Returns a new Elasticsearch client configured for the Dependabot alerts index.
    # This is broken out into a helper method so that it can be more easily mocked in tests.
    sig { returns(Search::Memex::Client) }
    def self.new_client
      Search::Memex::Client.new(Elastomer::Indexes::DependabotAlerts.new)
    end
  end
end
