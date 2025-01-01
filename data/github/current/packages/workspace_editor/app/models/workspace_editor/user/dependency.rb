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
    return true if self.feature_enabled?(:hadron_force_access)

    # Must have a repository to check code review access
    return false if repository.nil?

    # Must have copilot code review access
    PullRequests::Copilot::CodeReviewAccess.new(actor: owner, current_repository: repository).can_create_review_request?
  end
end
