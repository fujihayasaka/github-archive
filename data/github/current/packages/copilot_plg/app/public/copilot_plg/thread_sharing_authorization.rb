# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class ThreadSharingAuthorization
    include GitHub::Memoizer

    AUTHORIZED = :authorized
    FEATURE_IS_DISABLED = :feature_is_disabled
    FEATURE_IS_UNAVAILABLE = :feature_is_unavailable
    UNAUTHORIZED = :unauthorized
    USER_HAS_BUSINESS_PLAN = :user_has_business_plan
    USER_HAS_ENTERPRISE_PLAN = :user_has_enterprise_plan
    USER_HAS_PAID_ENTERPRISE_MEMBERSHIP = :user_has_paid_enterprise_membership
    USER_HAS_PAID_ORGANIZATION_MEMBERSHIP = :user_has_paid_organization_membership
    USER_IS_ENTERPRISE_MANAGED = :user_is_enterprise_managed
    USER_IS_UNKNOWN = :user_is_unknown

    sig { params(user: T.nilable(User)).void }
    def initialize(user:)
      @user = user
    end

    sig { returns(T::Boolean) }
    memoize def decision
      reason_user_cannot_share_copilot_thread.nil?
    end

    sig { returns(Symbol) }
    memoize def reason
      reason_user_cannot_share_copilot_thread || AUTHORIZED
    end

    sig { returns(T.nilable(String)) }
    memoize def message
      return nil if decision
      I18n.translate!(reason, scope: "copilot_plg.thread_sharing_authorization.messages", default: UNAUTHORIZED)
    end

    # This hash corresponds to keyword arguments accepted by the
    # MonolithTwirp::Copilotapi::Core::V1::AuthorizeThreadSharingResponse
    # class. This hash can be a subset of the arguments accepted by the Twirp
    # response class since they're all optional. But this hash must *not*
    # include an invalid keyword argument.
    sig { returns({ decision: T::Boolean, reason: String, message: T.nilable(String), has_private_references: T::Boolean }) }
    def to_hash
      { decision:, reason: reason.to_s, message:, has_private_references: false }
    end

    private

    sig { returns(T.nilable(Symbol)) }
    memoize def reason_user_cannot_share_copilot_thread
      return USER_IS_UNKNOWN unless @user
      return FEATURE_IS_UNAVAILABLE unless CopilotPLG.domain.copilot_thread_sharing_enabled?
      return FEATURE_IS_DISABLED unless @user.feature_enabled?(:copilot_share_conversation)

      # Let employees share unless the feature flag is explicitly disabled.
      return nil if @user.employee?

      # Spammy and suspended users can't share, but we hide those
      # classifications from the user.
      return FEATURE_IS_DISABLED if @user.spammy?
      return FEATURE_IS_DISABLED if @user.suspended?

      # EMUs can't share.
      return USER_IS_ENTERPRISE_MANAGED if @user.is_enterprise_managed?

      # Forbid sharing on Copilot for Business/Enterprise plans.
      copilot_user = Copilot::Public::User.new(@user)
      return USER_HAS_ENTERPRISE_PLAN if copilot_user.has_ce_access?
      return USER_HAS_BUSINESS_PLAN if copilot_user.has_cb_access?

      # If the user is a with a paid enterprise, no sharing.
      return USER_HAS_PAID_ENTERPRISE_MEMBERSHIP if @user.businesses(include_unaffiliated: true).any?(&:paid_plan?)

      # If the user is affiliated with a paid organization, no sharing.
      return USER_HAS_PAID_ORGANIZATION_MEMBERSHIP if @user.organizations.any?(&:paid_plan?)

      nil
    end
  end
end
