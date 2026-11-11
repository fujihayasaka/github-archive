# typed: true
# frozen_string_literal: true

module WorkspaceEditor::User::Dependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
  def workspace_editor_preview_enabled?(repository: nil)
    T.bind(self, ::User)
    # Must have editor feature preview on
    return false unless self.feature_preview_enabled?(:copilot_hadron_editor)

    # If force access is enabled, the user has access & bypasses all other checks
    return true if self.feature_flag_enabled_or_raise?(:hadron_force_access) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    # Must have a repository to check code review access
    return false if repository.nil?

    # we allow users to have copilot access through copilot code review or have appropriate GHAS access

    # GHAS is enabled by default for all public repositories. We only want to give access when a business is paying.
    return true if repository.business && CodeScanning::AutofixCodeql.allowed_by_business?(repository.business) && !repository.public?

    WorkspaceEditor::Access.new(actor: owner, current_repository: repository).has_workspace_editor_preview_access?
  end
end
