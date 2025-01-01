# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class SecretScanningAlertRevision < ApplicationRecord::SecurityOverviewAnalytics
    include RevisionCompressor

    self.table_name = "soa_secret_scanning_alert_revisions"

    after_initialize :alert_validity_will_change
    after_commit :update_feature_status_summary

    sig { void }
    def update_feature_status_summary
      return unless next_revision_date_id == Date::FUTURE_DATE_ID
      UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
    end

    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
    SecretScanningAlertResolution = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution
    SecretScanningTokenValidity = ::GitHub::Proto::SecretScanning::Types::V1::TokenValidity

    QUALIFIER_SECRET_TYPE = "secret-scanning.secret-type"
    QUALIFIER_SECRET_TYPE_ALIAS = "secret-type"
    QUALIFIER_PROVIDER = "secret-scanning.provider"
    QUALIFIER_PROVIDER_ALIAS = "provider"
    QUALIFIER_VALIDITY = "secret-scanning.validity"
    QUALIFIER_VALIDITY_ALIAS = "validity"
    QUALIFIER_BYPASSED = "secret-scanning.bypassed"

    RESOLUTIONS_MAPPING = T.let({
      fixed_or_revoked: [
        SecretScanningAlertResolution::REVOKED,
      ],
      auto_dismissed: [
        SecretScanningAlertResolution::PATTERN_DELETED,
        SecretScanningAlertResolution::PATTERN_EDITED,
      ],
      false_positive: [
        SecretScanningAlertResolution::FALSE_POSITIVE
      ],
      risk_accepted: [
        SecretScanningAlertResolution::USED_IN_TESTS,
        SecretScanningAlertResolution::WONT_FIX,
        SecretScanningAlertResolution::HIDDEN_BY_CONFIG,
      ]
    }.with_indifferent_access.freeze, T::Hash[T.any(String, Symbol), T::Array[Integer]])

    VALIDITIES_MAPPING = T.let({
      unknown: [
        SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN,
        SecretScanningTokenValidity::TOKEN_VALIDITY_UNVERIFIABLE
      ],
      inactive: [
        SecretScanningTokenValidity::TOKEN_VALIDITY_INACTIVE,
        SecretScanningTokenValidity::TOKEN_VALIDITY_REVOKED
      ],
      active: [
        SecretScanningTokenValidity::TOKEN_VALIDITY_ACTIVE
      ]
    }.with_indifferent_access.freeze, T::Hash[T.any(String, Symbol), T::Array[Integer]])

    sig { returns(String) }
    def self.feature_type
      "secret_scanning"
    end

    sig { params(filters: T::Array[Symbol]).returns(T::Array[Integer]) }
    def self.to_closure_reasons(filters)
      closure_reasons = []
      filters.each do |filter|
        closure_reasons << RESOLUTIONS_MAPPING[filter]
      end

      closure_reasons.flatten
    end

    sig { params(filters: T::Array[String]).returns(T::Array[String]) }
    def self.to_valid_severities(filters)
      # Ignore other severities because all SS alerts are considered critical
      filters.reject { |f| f != "critical" }
    end

    sig { params(filters: T::Array[Symbol]).returns(T::Array[Integer]) }
    def self.to_token_validities(filters)
      validities = []
      filters.each do |filter|
        validities << VALIDITIES_MAPPING[filter]
      end

      validities.flatten
    end

    sig { params(token_resolution: T.nilable(T.any(Symbol, Integer))).returns(T.nilable(Integer)) }
    def self.to_alert_resolution(token_resolution)
      alert_resolution = if token_resolution.is_a?(Symbol) && token_resolution != :NO_RESOLUTION
        SecretScanningAlertResolution.resolve(token_resolution)
      elsif token_resolution.is_a?(Integer) && token_resolution != 0
        token_resolution
      end

      alert_resolution
    end

    sig { params(token_validity: T.nilable(T.any(Symbol, Integer))).returns(T.nilable(Integer)) }
    def self.to_alert_validity(token_validity)
      alert_validity = if token_validity.nil?
        # nil == unknown in TSS. Since "unknown" is a queryable validity, it's better to store the enum
        # to simplify the query and avoid branching logic between unknown and other validity values.
        SecretScanningTokenValidity::TOKEN_VALIDITY_UNKNOWN
      elsif token_validity.is_a?(Symbol)
        SecretScanningTokenValidity.resolve(token_validity)
      else
        token_validity
      end
    end

    belongs_to :date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :secret_scanning_alert_revisions
    belongs_to :next_revision_date,
      class_name: SecurityOverviewAnalytics::Date.name,
      inverse_of: :last_secret_scanning_alert_revisions
    belongs_to :repository_metadata,
      class_name: SecurityOverviewAnalytics::Repository.name,
      foreign_key: :repository_id,
      inverse_of: :secret_scanning_alert_revisions
    belongs_to :repository, class_name: "::Repository"

    class UpdatePayload < T::Struct

      AnyTime = T.type_alias { T.any(ActiveSupport::TimeWithZone, Time) }

      const :alert_created_at, AnyTime
      const :alert_updated_at, AnyTime
      const :alert_resolved, T::Boolean
      const :alert_resolved_at, T.nilable(AnyTime)
      const :alert_resolution, T.nilable(Integer)
      const :alert_type, String
      const :alert_type_provider, String
      const :alert_type_slug, String
      const :alert_validity, T.nilable(Integer)
      const :alert_bypassed, T::Boolean, default: false
      # Make this mutable so we can update it in the upsert_revision method.
      prop :alert_validity_updated_at, T.nilable(AnyTime)

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.tap do |h|
          # 'serialize' omits nil values from the hash output,
          # so we need to fill them back in.
          h["alert_resolved_at"] = nil if self.alert_resolved_at.nil?
          h["alert_resolution"] = nil if self.alert_resolution.nil?
        end
      end

      sig { params(other: UpdatePayload).returns(T::Boolean) }
      def ==(other)
        serialize == other.serialize
      end
    end

    class TokenFilters < T::Struct

      const :token_type_slug, Filters::SecretScanning::ByTokenTypeSlug
      const :token_provider, Filters::SecretScanning::ByTokenProvider
      const :validity, Filters::SecretScanning::ByValidity
      const :bypassed, Filters::SecretScanning::ByBypassed

      sig { returns(T::Hash[String, T.untyped]) }
      def serialize
        super.tap do |h|
          h = h.with_indifferent_access
        end
      end

      sig { params(other: TokenFilters).returns(T::Boolean) }
      def ==(other)
        serialize == other.serialize
      end

      sig { returns(T::Boolean) }
      def any_applied?
        serialize.values.any? { |filter| !filter.is_empty? }
      end
    end

    sig do
      params(
        update_payload: UpdatePayload,
        repository_id: Integer,
        alert_number: Integer,
        force_rewrite: T::Boolean,
      ).void
    end
    def self.upsert_revision(update_payload, repository_id:, alert_number:, force_rewrite: false)
      # alert_validity is specific to secret scanning, so update the timestamp here instead of in the generic RevisionUpserter.
      date_id = Date.id_from_time(update_payload.alert_updated_at)
      prev_revision = self.fetch_previous_revision(repository_id:, alert_number:, date_id:)

      update_payload.alert_validity_updated_at = if prev_revision
        if prev_revision.alert_validity != update_payload.alert_validity
          # If the previous revision has a different validity state, we need to update the timestamp
          update_payload.alert_updated_at
        else
          # In all other cases, we need to keep the validity_updated_at timestamp from the previous revision if it exists.
          prev_revision.alert_validity_updated_at
        end
      end

      RevisionUpserter.new(self).upsert(update_payload, repository_id:, alert_number:, force_rewrite:)
    end

    sig { params(fields: T::Hash[Symbol, T.untyped], repository_id: Integer, alert_number: Integer).void }
    def self.upsert_revision_with_fields(fields, repository_id:, alert_number:)
      date_id = Date.id_from_time(fields[:alert_updated_at])
      prev_revision = self.fetch_previous_revision(repository_id:, alert_number:, date_id:)

      # If there is no previous revision, we should skip the upsert and let HydroSecretScanningAlertsChangedJob or reconciliation handle it.
      unless prev_revision
        GitHub.logger.info(
          "No initial revision. Skipping upsert.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.secret_scanning.upsert.repo_id": repository_id,
          "gh.security_overview_analytics.secret_scanning.upsert.alert_number": alert_number,
          "gh.security_overview_analytics.secret_scanning.upsert.fields_to_update": fields,
        )
        return
      end

      required_fields = UpdatePayload.props.select { |_, v| v[:immutable] }.keys
      prev_revision_hash = prev_revision.attributes.symbolize_keys.select { |k| required_fields.include?(k) }

      # Only update fields whose values have changed.
      new_revision_hash = prev_revision_hash.merge(fields)
      update_payload = SecretScanningAlertRevision::UpdatePayload.new(new_revision_hash)

      self.upsert_revision(update_payload, repository_id:, alert_number:, force_rewrite: false)
    end

    sig { params(repository_id: Integer, alert_number: Integer, date_id: Integer).returns(T.nilable(SecretScanningAlertRevision)) }
    def self.fetch_previous_revision(repository_id:, alert_number:, date_id:)
      self.where(repository_id:, alert_number:)
        .where("date_id <= ?", date_id)
        .order(date_id: :desc)
        .first
    end

    sig { params(repository_id: Integer, alert_number: Integer).void }
    def self.delete_alert_revisions(repository_id:, alert_number:)
      delete_alerts(repository_id:, alert_numbers: [alert_number])
    end

    sig { params(repository_id: Integer, alert_numbers: T::Array[Integer]).void }
    def self.delete_alerts(repository_id:, alert_numbers:)
      # In theory, we would never need to delete more than one batch since there can be only one revision per day.
      # Calling `in_batches` here is for safety concern in case something is wrong with data retention.
      self.where(repository_id:, alert_number: alert_numbers).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.secret_scanning_alert_revisions.deleted", batch_size)
        end
      end
    end

    sig { params(repository_ids: T::Array[Integer]).void }
    def self.delete_by_repository_ids(repository_ids)
      self.where(repository_id: repository_ids).in_batches do |batch|
        batch_size = batch.size
        self.throttle_writes_with_retry do
          batch.delete_all
          GitHub.dogstats.count("security_overview_analytics.secret_scanning_alert_revisions.deleted", batch_size)
        end
      end
    end

    sig { override.returns(T::Array[Symbol]) }
    def self.fields_to_serialize
      UpdatePayload.props.keys
    end

    sig { void }
    def alert_validity_will_change
      alert_validity_will_change! if !persisted?
    end

    sig { params(alert: SecretScanningAlert).returns(T::Array[Symbol]) }
    def fields_with_deviation(alert)
      output = T.let([], T::Array[Symbol])

      output << :alert_type if alert_type != alert.token_type
      output << :alert_type_provider if alert_type_provider != alert.token_type_provider
      output << :alert_type_slug if alert_type_slug != alert.slug
      output << :alert_resolved if alert_resolved != alert.resolved
      output << :alert_resolved_at if alert_resolved_at&.to_time&.utc != alert.resolved_at&.to_time&.utc
      output << :alert_bypassed if alert_bypassed != alert.bypassed

      validity = SecretScanningAlertRevision.to_alert_validity(alert.validity)
      output << :alert_validity if alert_validity != validity

      resolution = SecretScanningAlertRevision.to_alert_resolution(alert.resolution)
      output << :alert_resolution if alert_resolution != resolution

      output
    end
  end
end
