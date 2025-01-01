# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class Domain < GH::Domain::Base
    include GitHub::Middleware::AnonymousRequest

    LOGGED_OUT_COPILOT_CHAT_SECRET = "bigorca"

    # Returns whether Copilot thread sharing is available on the instance.
    sig { returns(T::Boolean) }
    def copilot_thread_sharing_enabled?
      !GitHub.single_or_multi_tenant_enterprise?
    end

    # Returns whether the given user can share and unshare Copilot threads.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def user_can_share_copilot_thread?(user)
      authorize_thread_sharing(user:).decision
    end

    # Returns whether the given user can view and continue shared Copilot
    # threads.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def user_can_read_shared_copilot_thread?(user)
      return false unless user
      return false unless copilot_thread_sharing_enabled?

      user.feature_flag_enabled_or_raise?(:copilot_read_shared_conversation) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    end

    # Returns a response containing an authorization decision, a
    # machine-readable reason, and a human-readable message for whether the
    # given user is allowed to share a Copilot thread.
    sig { params(user: T.nilable(User)).returns(CopilotPLG::ThreadSharingAuthorization) }
    def authorize_thread_sharing(user:)
      CopilotPLG::ThreadSharingAuthorization.new(user:)
    end

    # Returns if we should make the new logged-out Copilot chat experience
    # available for the given request. If an authenticated user is available,
    # it may also be provided.
    sig { params(request: ActionDispatch::Request, user: T.nilable(User)).returns(T::Boolean) }
    def logged_out_copilot_chat_enabled?(request, user: nil)
      # Allows logged-in staff to imitate a logged-out user via ?_features=
      return true if FeatureFlag.vexi.enabled_or_raise?(:copilot_chat_logged_out_experience_staff) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      # Allows staff to actor-enable the feature flag.
      return true if user&.feature_flag_enabled_or_raise?(:copilot_chat_logged_out_experience_staff) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      # Only render the logged-out experience when… logged out!
      return false unless anonymous_request?(request)

      # Feature flag controlling public access to the new logged-out experience
      return true if FeatureFlag.vexi.enabled_or_raise?(:copilot_chat_logged_out_experience) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      # Allows logged-out staff to test the new experience end-to-end when they
      # add a specific query parameter or cookie.
      return true if request.query_parameters[LOGGED_OUT_COPILOT_CHAT_SECRET].present? ||
        request.cookies[LOGGED_OUT_COPILOT_CHAT_SECRET].present?

      false
    end

    # Returns if we should show a logged out view for shared chat routes.
    sig { params(request: ActionDispatch::Request).returns(T::Boolean) }
    def logged_out_copilot_shared_chat_enabled?(request)
      !!(anonymous_request?(request) && FeatureFlag.vexi.enabled_or_raise?(:copilot_shared_chat_logged_out_experience)) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end
end
