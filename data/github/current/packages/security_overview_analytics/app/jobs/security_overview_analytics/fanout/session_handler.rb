# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module SessionHandler
      extend T::Helpers
      include GitHub::Memoizer

      abstract!
      requires_ancestor { TenantBaseJob }

      protected

      sig { returns(T::Boolean) }
      memoize def sessions_locked?
        fanout_action = action
        return true if fanout_action.nil?

        unlocked_sessions_by_action = feature_strategies.map { |strategy| strategy.unlocked_session }.compact.group_by(&:action)
        unlocked_initializations = unlocked_sessions_by_action[Types::Action::Initialize] || []
        unlocked_reconciliations = unlocked_sessions_by_action[Types::Action::Reconcile] || []

        if fanout_action == Types::Action::Initialize
          if unlocked_initializations.empty?
            GitHub.dogstats.increment(
              "security_overview_analytics.tenant_fanout.stopped",
              tags: all_stats_tags + ["reason:features_already_initialized"]
            )
            return true
          end
        elsif fanout_action == Types::Action::Reconcile
          if unlocked_initializations.size == feature_strategies.size
            GitHub.dogstats.increment(
              "security_overview_analytics.tenant_fanout.stopped",
              tags: all_stats_tags + ["reason:features_not_initialized"]
            )
            return true
          end

          if unlocked_reconciliations.empty?
            GitHub.dogstats.increment(
              "security_overview_analytics.tenant_fanout.stopped",
              tags: all_stats_tags + ["reason:features_reconciled_recently"]
            )
            return true
          end
        else
          T.absurd(fanout_action)
        end

        false
      end

      sig { params(is_last_batch: T::Boolean).void }
      def try_lock_sessions(is_last_batch)
        return unless is_last_batch
        lock_at = initial_start || initially_enqueued_at
        feature_strategies.each { |strategy| strategy.lock_session!(T.must(action), at: lock_at) }
      end

      sig { returns(T::Array[T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob))]) }
      memoize def available_fanout_jobs
        feature_strategies.map { |strategy| strategy.available_fanout_job(T.must(action)) }.uniq.compact
      end

      sig { params(fanout_job: T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob))).returns(T.nilable(Time)) }
      def last_session_locked_at(fanout_job)
        feature_strategies.find { |strategy| strategy.available_fanout_job(T.must(action)) == fanout_job }&.unlocked_session&.locked_at
      end

      private

      sig { returns(T::Array[Strategies::FeatureStrategy]) }
      memoize def feature_strategies
        features.compact.uniq.reduce(T.let([], T::Array[Strategies::FeatureStrategy])) do |memo, feature|
          strategy = Strategies::FeatureStrategyFactory.from_feature(feature, tenant: T.must(tenant), owner_type:)
          memo << strategy if strategy.feature_available?
          memo
        end
      end
    end
  end
end
