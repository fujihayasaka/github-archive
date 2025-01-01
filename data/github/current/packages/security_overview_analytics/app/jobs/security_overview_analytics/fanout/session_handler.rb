# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module SessionHandler
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer

      abstract!
      requires_ancestor { TenantBaseJob }

      DEFAULT_SESSION_TTL = T.let(7.days, ActiveSupport::Duration)

      protected

      sig { returns(T::Boolean) }
      memoize def sessions_locked?
        fanout_action = action
        return true if fanout_action.nil?

        unlocked_initializations, unlocked_reconciliations = unlocked_sessions_all_actions

        if fanout_action == Types::Action::Initialize
          if unlocked_initializations.empty?
            GitHub.dogstats.increment(
              "security_overview_analytics.tenant_fanout.stopped",
              tags: all_stats_tags + ["reason:features_already_initialized"]
            )
            return true
          end
        elsif fanout_action == Types::Action::Reconcile
          if unlocked_initializations.size == available_features.size
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
        unlocked_sessions_current_action.each do |session|
          session.lock!(at: initial_start || initially_enqueued_at)
        end
      end

      sig { returns(T::Array[T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob))]) }
      memoize def available_fanout_jobs
        if tenant_scope == Types::TenantScope::Business
          return [RepositoryOwnerJob] if unlocked_sessions_current_action.any?
        else
          return unlocked_sessions_current_action.reduce(T.let([], T::Array[T.class_of(RepositoryBaseJob)])) do |memo, session|
            if session.feature == Types::Feature::CodeScanningPullRequestAlert
              memo << Initialization::CodeScanningPullRequestAlertsJob if is_initialization?
              memo << Reconciliation::CodeScanningPullRequestAlertsJob if is_reconciliation?
            end
            memo
          end
        end

        []
      end

      sig { params(fanout_job: T.class_of(ApplicationJob)).returns(T.nilable(Time)) }
      def last_session_locked_at(fanout_job)
        sessions_by_feature = T.let(
          unlocked_sessions_current_action.index_by(&:feature),
          T::Hash[Types::Feature, Session]
        )

        if fanout_job == Initialization::CodeScanningPullRequestAlertsJob ||
          fanout_job == Reconciliation::CodeScanningPullRequestAlertsJob
          return sessions_by_feature[Types::Feature::CodeScanningPullRequestAlert]&.locked_at
        end

        nil
      end

      private

      sig { returns(T::Boolean) }
      memoize def is_initialization?
        action == Types::Action::Initialize
      end

      sig { returns(T::Boolean) }
      memoize def is_reconciliation?
        action == Types::Action::Reconcile
      end

      sig { params(feature: Types::Feature).returns(T::Boolean) }
      def is_feature_supported?(feature)
        if feature == Types::Feature::CodeScanningPullRequestAlert
          # Ignored by fanout from EMU owners
          return false if tenant_scope == Types::TenantScope::User
          # Ignored by business fanout for EMU owners
          return false if tenant_scope == Types::TenantScope::Business && owner_type == Types::Owner::User
          return true
        end

        false
      end

      sig { params(feature: Types::Feature).returns(T.nilable(ActiveSupport::Duration)) }
      def reconciliation_ttl_per_feature(feature)
        # Individual can have different TTL per their requirement
        DEFAULT_SESSION_TTL
      end

      sig { returns(T.nilable(Types::Owner)) }
      memoize def feature_prerequisite
        return nil unless tenant_scope == Types::TenantScope::Business
        owner_type
      end

      sig { returns(T::Array[Types::Feature]) }
      memoize def available_features
        features.compact.uniq.reduce(T.let([], T::Array[Types::Feature])) do |memo, feature|
          next memo unless is_feature_supported?(feature)
          memo << feature
          memo
        end
      end

      sig { returns([T::Array[Session], T::Array[Session]]) }
      memoize def unlocked_sessions_all_actions
        unlocked_initializations = T.let([], T::Array[Session])
        unlocked_reconciliations = T.let([], T::Array[Session])

        available_features.each do |feature|
          initialize_session = Session.new(
            action: Types::Action::Initialize,
            tenant_scope: T.must(tenant_scope),
            tenant_id:,
            feature: feature,
            feature_prerequisite: feature_prerequisite,
            expires: nil # Initialization session remains locked indefinitely until unlock method is called
          )
          next unlocked_initializations << initialize_session unless initialize_session.locked?

          # Uninitialized feature automatically considered as session locked for reconciliation.
          reconcile_session = Session.new(
            action: Types::Action::Reconcile,
            tenant_scope: T.must(tenant_scope),
            tenant_id:,
            feature: feature,
            feature_prerequisite: feature_prerequisite,
            expires: DEFAULT_SESSION_TTL
          )
          ttl = reconciliation_ttl_per_feature(feature)
          unlocked_reconciliations << reconcile_session unless reconcile_session.locked?(after: ttl&.ago)
        end

        [unlocked_initializations, unlocked_reconciliations]
      end

      sig { returns(T::Array[Session]) }
      memoize def unlocked_sessions_current_action
        unlocked_initializations, unlocked_reconciliations = unlocked_sessions_all_actions
        unlocked_sessions = unlocked_initializations if is_initialization?
        unlocked_sessions = unlocked_reconciliations if is_reconciliation?
        unlocked_sessions || []
      end
    end
  end
end
