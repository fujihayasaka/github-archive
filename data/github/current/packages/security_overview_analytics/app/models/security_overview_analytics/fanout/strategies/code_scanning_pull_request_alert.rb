# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Strategies
      class CodeScanningPullRequestAlert < FeatureStrategy
        RECONCILIATION_SESSION_TTL = T.let(7.days.freeze, ActiveSupport::Duration)
        RECONCILIATION_REPEAT_LIMIT = T.let(7.days.freeze, ActiveSupport::Duration)

        sig { override.returns(Types::Feature) }
        memoize def feature
          Types::Feature::CodeScanningPullRequestAlert
        end

        sig { override.returns(T::Boolean) }
        memoize def feature_available?
          # Not available on business fanout for EMU owners
          return false if @tenant_type == Types::TenantScope::Business && @owner_type == Types::Owner::User
          # Not available on EMU owners fanout
          return false if @tenant_type == Types::TenantScope::User
          true
        end

        sig { override.returns(T.nilable(Session)) }
        memoize def unlocked_session
          return nil unless feature_available?
          return initialization_session unless initialization_session.locked?
          return reconciliation_session unless reconciliation_session.locked?(after: RECONCILIATION_REPEAT_LIMIT.ago)
          nil
        end

        sig { override.params(action: Types::Action).returns(T.nilable(T.any(T.class_of(TenantBaseJob), T.class_of(RepositoryBaseJob)))) }
        def available_fanout_job(action)
          session = unlocked_session
          return nil if session.nil?
          return nil unless session.action == action
          return RepositoryOwnerJob if @tenant_type == Types::TenantScope::Business
          return Initialization::CodeScanningPullRequestAlertsJob if session.is_initialization?
          return Reconciliation::CodeScanningPullRequestAlertsJob if session.is_reconciliation?
          nil
        end

        sig { override.params(action: Types::Action, at: T.nilable(Time)).void }
        def lock_session!(action, at:)
          session = unlocked_session
          return if session.nil?
          return unless session.action == action
          session.lock!(at:)
        end

        private

        sig { returns(Session) }
        memoize def initialization_session
          Session.new(
            action: Types::Action::Initialize,
            tenant_scope: @tenant_type,
            tenant_id: T.cast(@tenant.id, Integer),
            feature: feature,
            feature_prerequisite: @owner_type,
            expires: nil
          )
        end

        sig { returns(Session) }
        memoize def reconciliation_session
          Session.new(
            action: Types::Action::Reconcile,
            tenant_scope: @tenant_type,
            tenant_id: T.cast(@tenant.id, Integer),
            feature: feature,
            feature_prerequisite: @owner_type,
            expires: RECONCILIATION_SESSION_TTL
          )
        end
      end
    end
  end
end
