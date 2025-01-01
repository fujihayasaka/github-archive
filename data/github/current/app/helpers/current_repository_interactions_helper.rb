# typed: false
# frozen_string_literal: true

module CurrentRepositoryInteractionsHelper
  include GitHub::Memoizer

  memoize def can_interact_with_repo?
    current_repository.can_be_interacted_with_by?(current_user, user_can_push: current_user_can_push?)
  end

  memoize def current_user_can_push?
    memoized_repo_auth[:pushable]
  end

  memoize def current_user_can_link_issues_and_prs?
    current_repository.issues_and_prs_linkable_by?(current_user)
  end

  memoize def current_user_can_write_wiki?
    current_repository.wiki_writable_by?(current_user, user_can_pull: current_user_can_read_repo?, user_can_push: current_user_can_push?)
  end

  memoize def current_user_can_read_repo?
    return false unless current_repository

    memoized_repo_auth[:pullable]
  end

  memoize def memoized_repo_auth
    pullable, pushable = Promise.all([
      current_repository.async_pullable_by?(current_user),
      current_repository.async_authorized_to_write?(current_user),
    ]).sync

    { pullable: pullable, pushable: pushable }
  end
end
