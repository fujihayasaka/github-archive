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
        return false unless GitHub.dependabot_es_search_enabled?
        DEPENDABOT_ALERTS_SEARCH_INDEX_FIELDS.any? { |field| saved_change_to_attribute?(field) }
      end

      # Returns the data for this range to be indexed for Dependabot Alerts.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def dependabot_alert_fields
        data = {
          package_name: affects,
          ecosystem: ecosystem,
          has_patch: fixed_in.present?
        }
        # The return value is always 32bit, but can be interpreted as unsigned.  Elasticsearch's integer
        # field is signed, so we need to ensure that the values are always within -2^31 to 2^31-1.
        # Packing as unsigned and then unpacking as signed ensures a signed value
        data[:vulnerable_version_range_checksum] = [Zlib.crc32(data.to_s)].pack("L").unpack("l").first
        data
      end

      # Starts background processing to synchronize
      # changes to the dependabot alerts search index.
      sig { void }
      def synchronize_dependabot_alerts_search_index
        Search::DependabotAlerts::BatchUpdateElasticsearchJob.perform_later(
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
