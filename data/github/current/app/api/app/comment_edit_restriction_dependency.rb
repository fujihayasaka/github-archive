# typed: true
# frozen_string_literal: true

module Api::App::CommentEditRestrictionDependency
  extend T::Helpers

  requires_ancestor { Api::App }

  # Ensures that the current user is allowed to edit or delete the given comment.
  #
  # When the :restrict_pr_comment_editing_to_authors feature flag is enabled for
  # the repository owner, only the comment author, repository owner or a repository admin may
  # edit/delete the comment. The associated integrations are allowed through.
  #
  # For issue comments, pass the associated issue so that pure-issue comments
  # (non-PR) are exempted from the restriction.
  def ensure_comment_edit_allowed!(repo:, resource:, issue: nil)
    return if current_integration
    return if !FeatureFlag.vexi.enabled?(:restrict_pr_comment_editing_to_authors, repo.owner, default: false)
    return if issue && !issue.pull_request?
    return if resource.authored_by?(current_user)
    return if repo.permit?(current_user, :admin)

    deliver_error! 403
  end
end
