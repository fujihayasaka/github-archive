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

      return false unless feature_flag_enabled_in_hierarchy?(@repository, FeatureFlags::SECRET_SCANNING_ALERT_ASSIGNEE)

      return false unless @repository.writable_by?(assigned_user)

      current_user.id == assigned_user.id
    end
  end
end
