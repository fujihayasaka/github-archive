# typed: strict
# frozen_string_literal: true

module CopilotPLG
  class Domain < GH::Domain::Base
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

      user.feature_enabled?(:copilot_read_shared_conversation)
    end

    # Returns a response containing an authorization decision, a
    # machine-readable reason, and a human-readable message for whether the
    # given user is allowed to share a Copilot thread.
    sig { params(user: T.nilable(User)).returns(CopilotPLG::ThreadSharingAuthorization) }
    def authorize_thread_sharing(user:)
      CopilotPLG::ThreadSharingAuthorization.new(user:)
    end
  end
end
