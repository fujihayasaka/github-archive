# typed: strict
# frozen_string_literal: true

require_relative "../../../../../security_products/app/models/security_center/k_v"

module SecurityOverviewAnalytics
  module Fanout
    class Session
      extend T::Sig
      include GitHub::Memoizer

      sig { returns(Types::Action) }; attr_reader :action
      sig { returns(Types::TenantScope) }; attr_reader :tenant_scope
      sig { returns(Integer) }; attr_reader :tenant_id
      sig { returns(Types::Feature) }; attr_reader :feature
      sig { returns(T.nilable(Types::Owner)) }; attr_reader :feature_prerequisite
      sig { returns(T.nilable(ActiveSupport::Duration)) }; attr_reader :expires

      sig do
        params(
          action: Types::Action,
          tenant_scope: Types::TenantScope,
          tenant_id: Integer,
          feature: Types::Feature,
          feature_prerequisite: T.nilable(Types::Owner),
          expires: T.nilable(ActiveSupport::Duration)
        ).void
      end
      def initialize(action:, tenant_scope:, tenant_id:, feature:, feature_prerequisite: nil, expires: nil)
        @action = action
        @tenant_scope = tenant_scope
        @tenant_id = tenant_id
        @feature = feature
        @feature_prerequisite = feature_prerequisite
        @expires = expires
      end

      sig { returns(String) }
      memoize def key
        prefix = "security_overview_analytics.#{action.serialize}_fanout_session"
        scope = "#{tenant_scope.serialize}_#{tenant_id}"
        feature_prefix = feature_prerequisite.present? ? "#{feature_prerequisite&.serialize}_" : ""
        "#{prefix}.#{scope}.#{feature_prefix}#{feature.serialize}"
      end

      sig { returns(T.nilable(Time)) }
      def locked_at
        return @_locked_at if defined?(@_locked_at)

        val = T.let(SecurityCenter::KV.store.get(key).value { nil }, T.nilable(String))
        @_locked_at = T.let(val&.to_time&.utc, T.nilable(Time))
      end

      sig { params(after: T.nilable(Time)).returns(T::Boolean) }
      def locked?(after: nil)
        return false unless locked_at.present?
        return true unless after.present?
        T.must(locked_at) > after
      end

      sig { returns(T.nilable(Time)) }
      def ttl
        val = SecurityCenter::KV.store.ttl(key).value { nil }
        val&.to_time&.utc
      end

      sig { params(at: T.nilable(Time)).returns(Time) }
      def lock!(at: nil)
        new_locked_at = at || Time.now.utc

        ThrottleHelper.throttle_kv_writes_with_fallback do
          SecurityCenter::KV.store.set(key, new_locked_at.iso8601(3), expires: expires&.from_now)
        end
        flush_locked_at_cache(new_locked_at)

        log(:session_locked)

        new_locked_at
      end

      sig { void }
      def unlock!
        ThrottleHelper.throttle_kv_writes_with_fallback do
          SecurityCenter::KV.store.del(key)
        end
        flush_locked_at_cache(nil)

        log(:session_unlocked)
      end

      private

      sig { params(save_type: Symbol).void }
      def log(save_type)
        GitHub.logger.info(
          "Fanout session saved.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.fanout.session.save_type": save_type,
          "gh.security_overview_analytics.fanout.session.key": key,
          "gh.security_overview_analytics.fanout.session.expires": expires&.inspect,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.fanout_session.saved",
          tags: [
            "save_type:#{save_type}",
            "action:#{action.serialize}",
            "tenant_scope:#{tenant_scope.serialize}",
            "feature:#{feature.serialize}",
            "feature_prerequisite:#{feature_prerequisite&.serialize || "nil"}"
          ]
        )
      end

      sig { params(locked_at: T.nilable(Time)).void }
      def flush_locked_at_cache(locked_at)
        @_locked_at = T.let(locked_at, T.nilable(Time))
      end
    end
  end
end
