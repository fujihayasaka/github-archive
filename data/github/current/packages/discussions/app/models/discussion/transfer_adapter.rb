# typed: true
# frozen_string_literal: true

module Discussion::TransferAdapter
  extend T::Helpers

  requires_ancestor { Discussion }

  REPOSITORY_LIMIT = 1000

  # Public: Is this discussion in a state such that it could be transferred
  # to another repository?
  sig { returns T.nilable(T::Boolean) }
  def can_be_transferred?
    return false unless open? || closed?
    return false if locked?
    repository = self.repository
    repository&.discussions_active? && !repository.archived?
  end

  # Public: Can the given actor transfer this discussion to another repository?
  sig { params(actor: T.untyped, modifiable_by_actor: T.untyped).returns(T.untyped) }
  def transferrable_by?(actor, modifiable_by_actor: nil)
    if modifiable_by_actor.nil?
      can_be_transferred? && modifiable_by?(actor)
    else
      can_be_transferred? && modifiable_by_actor
    end
  end

  # Public: Can this discussion be moved to the given repository by the given user?
  #
  # new_repo - a Repository
  # actor - the current User
  #
  # Returns a Boolean.
  sig { params(new_repo: T.untyped, actor: T.untyped).returns(T.untyped) }
  def can_transfer_to?(new_repo, actor:)
    # Can't transfer to a repo that doesn't have Discussions turned on
    return false unless new_repo&.discussions_active?

    # Can't transfer to a repo with a different owner
    return false unless repository && new_repo.owner_id == T.must(repository).owner_id

    # Can't transfer into an archived repository
    return false if new_repo.archived?

    # User lacks permission on this discussion to transfer it
    return false unless transferrable_by?(actor)

    # User requires write permission on new repo to transfer there
    return false unless new_repo.resources.contents.writable_by?(actor)

    # Can't transfer from private->public repo
    return false if !public? && new_repo.public?

    true
  end

  sig { params(viewer: T.untyped, supports_polls: T.untyped, query: T.untyped).returns(T.untyped) }
  def filter_repos_by_supports(viewer:, supports_polls:, query: nil)
    async_repository.then do |repository|
      # Grab other repositories by the same owner as this discussion's
      # current repository:
      target_repo_scope = Repository.active.where(owner_id: T.must(repository).owner_id).
        filter_spam_and_disabled_for(viewer).
        not_archived_scope

      target_repo_scope = target_repo_scope.private_scope if T.must(repository).private?
      target_repo_scope = target_repo_scope.search(query) if query.present?

      # Exclude this discussion's repository:
      target_repo_scope_ids = target_repo_scope.limit(REPOSITORY_LIMIT).pluck(:id) - [repository_id]

      if supports_polls?
        repo_with_poll_category_scope_ids = DiscussionCategory.where(repository_id: target_repo_scope_ids, supports_polls: true).pluck(:repository_id).uniq
        target_repo_scope_ids = target_repo_scope_ids.intersection(repo_with_poll_category_scope_ids)
      end

      repository_ids = viewer.associated_repository_ids(min_action: :write,
        repository_ids: target_repo_scope_ids)
      repos = Repository.where(id: repository_ids).order(updated_at: :desc)
      Configurable.preload_configuration(repos).select(&:discussions_active?)
    end
  end

  # Public: Get repositories this discussion could be transferred to.
  #
  # viewer - the currently authenticated User or nil
  # query - optional String to filter repositories by
  #
  # Returns a Promise resolving to a list of Repositories.
  sig { params(viewer: T.untyped, query: T.untyped).returns(T.untyped) }
  def async_possible_transfer_repositories(viewer:, query: nil)
    filter_repos_by_supports(viewer: viewer, query: query, supports_polls: poll.present?)
  end
end
