# typed: strict
# frozen_string_literal: true

require_relative "../../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  module Reconciliation
    class Session
      extend T::Helpers
      include GitHub::Memoizer

      INCREMENTAL_SESSION_DURATION_IN_MINS = T.let(1.day.in_minutes, Float)
      FULL_SCAN_SESSION_DURATION_IN_MINS = T.let(14.days.in_minutes, Float)

      sig { returns(Integer) }; attr_reader :owner_id
      sig { returns(T.nilable(String)) }; attr_reader :type

      BUSINESS_METRICS = T.let([
        Initialization::Type::Users.serialize,
        Initialization::Type::Organizations.serialize
      ].freeze, T::Array[String])

      REPO_METRICS = T.let([
        Initialization::Type::RepositoryMetadata.serialize,
        Initialization::Type::FeatureEnablement.serialize
      ].freeze, T::Array[String])

      ALERT_METRICS = T.let([
        Initialization::Type::CodeScanningAlert.serialize,
        Initialization::Type::SecretScanningAlert.serialize,
        Initialization::Type::DependabotAlerts.serialize
      ].freeze, T::Array[String])

      sig { returns(String) }
      def session_key
        T.let("#{OrganizationReconciliationJob.name}:#{owner_id}:#{type}", String)
      end

      sig { returns(String) }
      def id
        # If previous lock time is nil, this means that this is the first ever reconciliation for this org.
        # Assign only the org id to indicate first session.
        if session_started_at
          T.let("#{owner_id}.#{session_started_at}", String)
        else
          T.let("#{owner_id}", String)
        end
      end

      sig { params(owner_id: Integer, type: String).void }
      def initialize(owner_id:, type:)
        raise ArgumentError, "Type is not valid" unless type.in?(REPO_METRICS) || type.in?(ALERT_METRICS) || type.in?(BUSINESS_METRICS)
        @owner_id = owner_id
        @type = type
      end

      sig { returns(T.nilable(Time)) }
      def session_started_at
        return @_session_started_at if defined?(@_session_started_at)

        val = T.let(SecurityCenter::KV.store.get(session_key).value { nil }, T.nilable(String))
        val = T.let(val.to_time.utc, Time) if val

        @_session_started_at = T.let(val, T.nilable(Time))
      end

      sig { returns(T.nilable(Time)) }
      def ttl
        val = SecurityCenter::KV.store.ttl(session_key).value { nil }
        val&.to_time&.utc
      end

      sig { returns(T::Boolean) }
      def locked?
        return false unless session_started_at

        # If the timestamp from last reconciliation run is still within the cooldown period, skip this run.
        ((Time.now.utc - T.must(session_started_at)) / 1.minute).floor < INCREMENTAL_SESSION_DURATION_IN_MINS
      end

      sig { returns(T::Hash[Symbol, Time]) }
      def lock!
        # For alert metrics, we want to store the timestamp of the last reconciliation run.
        # Unlike repo metrics, alerts won't have an expiration time.
        last_session_started_at = session_started_at
        new_session_started_at = Time.now.utc

        ActiveRecord::Base.connected_to(role: :writing) do
          SecurityCenter::KV.store.set(session_key, new_session_started_at.to_s, expires:)
        end

        update_memoized_timestamp(session_started_at: new_session_started_at)

        GitHub.logger.info(
          "Session locked.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.owner.id": owner_id,
          "gh.security_overview_analytics.reconciliation.session.timestamp": new_session_started_at,
          "gh.security_overview_analytics.reconciliation.session.expires": expires,
          "gh.security_overview_analytics.reconciliation.type": @type,
        )
        GitHub.dogstats.increment("security_overview_analytics.reconciliation_session.start", tags: [@type])

        {
          session_started_at: new_session_started_at,
          last_session_started_at:,
        }
      end

      sig { params(last_session_started_at: T.nilable(Time)).void }
      def reset!(last_session_started_at:)
        # Reset session to last reconciliation run, if exists. If type is repo metrics, always delete the entire entry.
        if @type.in?(REPO_METRICS) || last_session_started_at.nil?
          ActiveRecord::Base.connected_to(role: :writing) do
            SecurityCenter::KV.store.del(session_key)
          end
          update_memoized_timestamp(session_started_at: nil)
        else
          ActiveRecord::Base.connected_to(role: :writing) do
            SecurityCenter::KV.store.set(session_key, last_session_started_at.to_s, expires:)
          end
          update_memoized_timestamp(session_started_at: last_session_started_at)
        end

        GitHub.logger.info(
          "Session reset.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.owner.id": owner_id,
          "gh.security_overview_analytics.reconciliation.session.timestamp": last_session_started_at,
          "gh.security_overview_analytics.reconciliation.session.expires": expires,
          "gh.security_overview_analytics.reconciliation.type": type,
        )
        GitHub.dogstats.increment("security_overview_analytics.reconciliation_session.reset", tags: ["type:#{type}"])
      end

      private

      sig { returns(::User) }
      def owner
        User.find_by!(id: owner_id)
      end

      sig { returns(T.nilable(Time)) }
      memoize def expires
        return INCREMENTAL_SESSION_DURATION_IN_MINS.minutes.from_now.to_time if type.in?(REPO_METRICS)

        current_expiry_time = SecurityCenter::KV.store.ttl(session_key).value { nil }
        current_expiry_time || FULL_SCAN_SESSION_DURATION_IN_MINS.minutes.from_now.to_time
      end

      sig { params(session_started_at: T.nilable(Time)).void }
      def update_memoized_timestamp(session_started_at:)
        @_session_started_at = T.let(session_started_at, T.nilable(Time))
      end
    end
  end
end
