# typed: true
# frozen_string_literal: true

module SpammyCommitAuthorBlocking
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { GitContentController }

  private

  def block_spammy_commit_author
    return unless FeatureFlag.vexi.enabled?(:block_spammy_commit_authors, current_user, default: false)
    return unless GitHub.spamminess_check_enabled?
    return if current_commit.nil?

    # Staff can always view commits
    return if current_user&.has_staff_role?

    # Return if author is not spammy
    return unless current_commit.author&.spammy?

    # Check if commit exists in branch, otherwise potentially spoofed commit
    return unless current_repository.branch_contains(current_commit.oid).empty?

    # 404 in cases of spammy user and potentially spoofed commit
    render_404
  end
end
