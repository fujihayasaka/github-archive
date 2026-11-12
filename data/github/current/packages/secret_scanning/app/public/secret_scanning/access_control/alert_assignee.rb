# typed: strict
# frozen_string_literal: true

module SecretScanning::AccessControl
  class AlertAssignee
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    # Checks if the user can access an alert because they are assigned to it
    # and the assignee feature flag is enabled
    sig { params(current_user: User, assigned_user: T.nilable(User)).returns(T::Boolean) }
    def has_access_as_assignee?(current_user, assigned_user)
      return false unless assigned_user.present?

      return false unless @repository.writable_by?(assigned_user)

      current_user.id == assigned_user.id
    end

    # Checks if a user is eligible to be assigned to an alert in this repository.
    #
    # This is the single source of truth for assignee eligibility and must match
    # the scope used to build the assignee picker, otherwise the two can drift and
    # a caller can assign an alert to a user the picker would never have offered.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def assignable?(user)
      return false if user.nil?
      return false if user.suspended?

      @repository.writable_by?(user)
    end
  end
end
