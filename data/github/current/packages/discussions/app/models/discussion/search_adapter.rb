# typed: true
# frozen_string_literal: true

module Discussion::SearchAdapter
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Discussion }

  # This is a set of checks against the discussion's parent repo, to determine
  # if it should be removed from the index. Since these are repo-level checks,
  # if the repo is found to be unsearchable, a delete of _all discussions for that repo_
  # from the index will be triggered. Handle individual discussion-shouldn't-be-searchable
  # events from inside prune_discussion method directly, not here.
  #
  # Some reasons the parent repo might not be searchable:
  #   - repo not routed on the file servers
  #   - repo's user is a spammer
  #   - disabled by an admin
  #   - no associated discussions
  #
  # Return `true` if we should add the discussion to the search index; return
  # `false` if we should not.
  sig { returns T::Boolean }
  def parent_repo_is_searchable?
    repository = self.repository
    return false unless repository&.active?

    # When the parent repo user is spammy
    return false if repository.spammy?

    # When the parent repo has been disabled for any reason
    return false if repository.disabled?

    # If the feature has been turned off for the repository,
    # shouldn't index the repository's discussions
    return false unless repository.discussions_active?

    # When the parent repo has been disabled for DMCA and similar reasons
    return false if repository.access.disabled?

    # The discussion is safe to index
    true
  end

  # Public: Synchronize this discussion with its representation in the search
  # index. If the discussion is newly created or modified in some fashion, then it
  # will be updated in the search index. If the discussion has been destroyed, then
  # it will be removed from the search index.
  sig { void }
  def synchronize_search_index
    if destroyed?
      RemoveFromSearchIndexJob.perform_later("discussion", id, repository_id)
    else
      # NOTE: If we ever change this, be sure to also update `reassign_discussions`
      # in `Discussions::CategoriesController`.
      Search.add_to_search_index("discussion", id)
    end
    self
  end
end
