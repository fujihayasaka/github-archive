# typed: strict
# frozen_string_literal: true

module Search
  module DependabotAlerts
    module CVEEPSS
      extend T::Helpers
      extend ActiveSupport::Concern

      requires_ancestor { ::CVEEPSS }

      # Fields from CVEEPSS's that populate the Dependabot Alerts search index.
      # When new data from a range is added to the index, update this list as well as
      # #dependabot_alert_fields below.
      DEPENDABOT_ALERTS_SEARCH_INDEX_FIELDS = [:percentage].freeze

      # Returns true if the Dependabot Alerts search index needs to be updated.
      sig { returns(T::Boolean) }
      def synchronize_dependabot_search_index?
        return false if vulnerability.nil?
        return false unless vulnerability&.feature_flag_enabled?(:dependabot_epss_bulk_write_to_elasticsearch, default: false)
        DEPENDABOT_ALERTS_SEARCH_INDEX_FIELDS.any? { |field| saved_change_to_attribute?(field) }
      end

      # Returns the data for this cve epss to be indexed for Dependabot Alerts.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def dependabot_alert_fields
        {
          epss_percentage: percentage,
        }
      end

      # Starts background processing to update the `search_index_updated_at` value
      # for all associated RepositoryVulnerabilityAlert database records, and to synchronize
      # changes to the dependabot alerts search index.
      sig { void }
      def synchronize_dependabot_alerts_search_index
        Search::DependabotAlerts::UpdateSearchIndexUpdatedAtJob.perform_later(
          updated_model: T.cast(self, ::CVEEPSS)
        )
      rescue StandardError => e
        Failbot.report(
          e,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.cve_epss.id" => id,
          "gh.vulnerability.id" => T.must(vulnerability).id,
        )
      end
    end
  end
end
