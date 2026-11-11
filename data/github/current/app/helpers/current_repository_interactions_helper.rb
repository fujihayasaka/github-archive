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

  memoize def current_user_can_create_prs?
    PullRequestActivationConfig.new(current_repository).pull_requests_enabled? && PullRequestCreationConfig.new(current_repository).pull_request_creation_allowed_for?(current_user)
  end

  # Returns a hash with PR limit display info for the current user and repository, or nil if the
  # limit doesn't apply (disabled, user has write access, or user is on the bypass list).
  #
  # Hash keys: limit (Integer), reached (Boolean)
  memoize def current_user_pr_create_limit_info
    return nil unless logged_in? && current_user && current_repository

    config = PullRequestCreationConfig.new(current_repository)
    return nil unless config.pull_request_creation_cap_applicable_to_user?(current_user)

    limit = config.pull_request_creation_cap
    reached = config.limit_reached_for_user?(current_user)
    { limit: limit, reached: reached }
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
