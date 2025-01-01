# typed: strict
# frozen_string_literal: true

# This job is an asynchronous wrapper around Search::DependabotAlerts::BulkUpdate.update_all_matching
# which allows bulk updates to be performed in the background.  It's signature is intended to match
# that of Search::DependabotAlerts::BulkUpdate.update_all_matching as closely as possible.

module Search
  module DependabotAlerts
    class BulkUpdateSearchIndexJob < ApplicationJob
      queue_as :index_bulk

      ELASTICSEARCH_RETRYABLE_ERRORS = [
        ElastomerClient::Client::ServerError,
        ElastomerClient::Client::IndexNotFoundError
      ].freeze

      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      retry_on *ELASTICSEARCH_RETRYABLE_ERRORS, wait: :polynomially_longer

      sig do
        params(
          filters: T::Hash[Symbol, T.untyped],
          attributes: T::Hash[Symbol, T.untyped],
          updated_at: T.nilable(ActiveSupport::TimeWithZone),
          log_tags: T::Hash[T.any(String, Symbol), T.untyped],
          stats_tags: T::Array[String]
        ).void
      end
      def perform(filters:, attributes:, updated_at:, log_tags:, stats_tags:)
        Search::DependabotAlerts::BulkUpdate.update_all_matching(
          filters:,
          attributes:,
          updated_at:,
          log_tags:,
          stats_tags:
        )
      end
    end
  end
end
