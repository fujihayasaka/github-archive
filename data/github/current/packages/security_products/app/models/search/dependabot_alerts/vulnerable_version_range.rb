# typed: strict
# frozen_string_literal: true

module Search
  module DependabotAlerts
    module VulnerableVersionRange
      extend T::Helpers
      extend ActiveSupport::Concern

      requires_ancestor { ::VulnerableVersionRange }

      # Fields from VulnerableVersionRanges that populate the Dependabot Alerts search index.
      # When new data from a range is added to the index, update this list as well as
      # #dependabot_alert_fields below.
      DEPENDABOT_ALERTS_SEARCH_INDEX_FIELDS = [:affects, :ecosystem, :fixed_in].freeze

      # Returns true if the Dependabot Alerts search index needs to be updated.
      sig { returns(T::Boolean) }
      def synchronize_dependabot_search_index?
        return false unless self.feature_flag_enabled?(:dependabot_vvr_bulk_write_to_elasticsearch, default: false)
        DEPENDABOT_ALERTS_SEARCH_INDEX_FIELDS.any? { |field| saved_change_to_attribute?(field) }
      end

      # Returns the data for this range to be indexed for Dependabot Alerts.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def dependabot_alert_fields
        {
          package_name: affects,
          ecosystem: ecosystem,
          has_patch: fixed_in.present?
        }
      end

      # Starts background processing to update the `search_index_updated_at` value
      # for all associated RepositoryVulnerabilityAlert database records, and to synchronize
      # changes to the dependabot alerts search index.
      sig { void }
      def synchronize_dependabot_alerts_search_index
        Search::DependabotAlerts::UpdateSearchIndexUpdatedAtJob.perform_later(
          updated_model: T.cast(self, ::VulnerableVersionRange)
        )
      rescue StandardError => e
        Failbot.report(
          e,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.vulnerable_version_range.id" => id,
        )
      end
    end
  end
end
