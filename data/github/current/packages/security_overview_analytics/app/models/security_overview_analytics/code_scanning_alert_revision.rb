# typed: strict
# frozen_string_literal: true

require "turboscan"

module SecurityOverviewAnalytics
  class CodeScanningAlertRevision < ApplicationRecord::SecurityOverviewAnalytics
    include RevisionCompressor
    include BulkActionHelper

    self.table_name = "soa_code_scanning_alert_revisions"

    after_commit :update_feature_status_summary

    sig { void }
    def update_feature_status_summary
      return unless next_revision_date_id == Date::FUTURE_DATE_ID
      UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
    end

    CodeScanningResolutions = ::Turboscan::Proto::ResultResolution

    QUALIFIER_CODEQL_RULE = "codeql.rule"
    QUALIFIER_THIRD_PARTY_RULE = "third-party.rule"

    RESOLUTIONS_MAPPING = T.let({
      fixed_or_revoked: [
        nil, # we store `nil` instead of :NO_RESOLUTION
      ],
      false_positive: [
        CodeScanningResolutions::FALSE_POSITIVE
      ],
      risk_accepted: [
        CodeScanningResolutions::WONT_FIX,
        CodeScanningResolutions::USED_IN_TESTS,
      ]
    }.with_indifferent_access.freeze, T::Hash[T.any(String, Symbol), T::Array[Integer]])

    sig { returns(String) }
    def self.feature_type
      "code_scanning"
    end

    sig { params(filters: T::Array[Symbol]).returns(T::Array[Integer]) }
    def self.to_closure_reasons(filters)
      closure_reasons = []
      filters.each do |filter|
        closure_reasons << RESOLUTIONS_MAPPING[filter]
      end

      closure_reasons.flatten
    end

    belongs_to :date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :code_scanning_alert_revisions
    belongs_to :next_revision_date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :last_code_scanning_alert_revisions
    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :code_scanning_alert_revisions
    include ::Repositories::BelongsToRepository
    belongs_to_repository_via_domain class_name: "::Repository"

    sig do
      params(
        update_payload: UpdatePayload,
        repository_id: Integer,
        alert_number: Integer,
        force_rewrite: T::Boolean,
        alert_id: T.nilable(Integer)
      ).void
    end
    def self.upsert_revision(update_payload, repository_id:, alert_number:, force_rewrite: false, alert_id: nil)
      RevisionUpserter.new(self).upsert(update_payload, repository_id:, alert_number:, force_rewrite:, alert_id:)
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.code_scanning_alert_revisions.deleted", batch_size)
        end
      end
    end

    sig { returns(T::Boolean) }
    def self.write_alert_number?
      # In GHES, we would need to start writing incrementally before a backfill. However, we don't know when that
      # work will get completed, so in the meantime we should keep the data as-is.
      # Tracking issue: https://github.com/github/security-center/issues/6296
      !GitHub.enterprise?
    end

    sig { override.returns(T::Array[Symbol]) }
    def self.fields_to_serialize
      UpdatePayload.props.keys
    end

    class UpdatePayload < T::Struct

      AnyTime = T.type_alias { T.any(ActiveSupport::TimeWithZone, Time) }

      const :alert_created_at, AnyTime
      const :alert_updated_at, AnyTime
      const :alert_severity, T.nilable(String)
      const :tool, String
      const :rule_sarif_identifier, String
      const :language, T.nilable(String)
      const :ref, T.nilable(String)
      const :alert_resolved, T::Boolean
      const :alert_resolved_at, T.nilable(AnyTime)
      const :alert_resolution, T.nilable(Integer)
      const :alert_id, T.nilable(Integer)
      const :has_autofix, T.nilable(T::Boolean)
      const :autofix_accepted, T.nilable(T::Boolean)

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.tap do |h|
          # 'serialize' omits nil values from the hash output,
          # so we need to fill them back in.
          h["alert_severity"] = nil if self.alert_severity.nil?
          h["alert_resolved_at"] = nil if self.alert_resolved_at.nil?
          h["alert_resolution"] = nil if self.alert_resolution.nil?
          h["has_autofix"] = nil if has_autofix.nil?
          h["autofix_accepted"] = nil if autofix_accepted.nil?
        end
      end

      sig { params(other: UpdatePayload).returns(T::Boolean) }
      def ==(other)
        serialize == other.serialize
      end
    end

    class RuleFilters < T::Struct

      const :codeql, Filters::CodeScanning::ByRule
      const :third_party, Filters::CodeScanning::ByRule

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.with_indifferent_access
      end
    end

    sig { params(other: CodeScanningAlertRevision).returns(T::Boolean) }
    def ==(other)
      # Check if two revisions has the same states
      return false if self.alert_resolved != other.alert_resolved
      return false if self.alert_resolution != other.alert_resolution
      return false if self.alert_resolved_at != other.alert_resolved_at
      return false if self.alert_reopened_at != other.alert_reopened_at

      # Check if two revisions have the same metadata
      return false if self.alert_severity != other.alert_severity
      return false if self.tool != other.tool
      return false if self.rule_sarif_identifier != other.rule_sarif_identifier
      return false if self.language != other.language
      return false if self.ref != other.ref

      # Check if two revisions were introduced at the same time
      return false if self.alert_created_at != other.alert_created_at

      # Otherwise, consider two revisions are the same
      true
    end
  end
end
