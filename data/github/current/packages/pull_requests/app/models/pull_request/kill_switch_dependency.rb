# typed: strict
# frozen_string_literal: true

module PullRequest::KillSwitchDependency
  extend T::Helpers

  requires_ancestor { PullRequest }

  KILL_SWITCH_FLAG = :pull_request_kill_switch

  # Public: Check if this pull request has the kill switch enabled.
  #
  # Returns Boolean.
  sig { returns(T::Boolean) }
  def killed?
    FeatureFlag.vexi.enabled?(KILL_SWITCH_FLAG, T.cast(self, PullRequest), default: false)
  end

  # Public: Returns true if this PR is killed and should be hidden from the given user.
  # Site admins and repository admins can still see killed PRs.
  #
  # user - The User viewing the PR (may be nil for anonymous).
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def killed_and_hidden_from?(user)
    return false unless killed?
    return true if user.nil?
    return false if user.site_admin?

    is_admin = GitHub::DomainIsolation.within_domain_of(Repository) { T.must(repository).adminable_by?(user) }
    !is_admin
  end

  # Public: Async version of killed_and_hidden_from? for use in Promise chains.
  #
  # user - The User viewing the PR (may be nil for anonymous).
  #
  # Returns Promise<Boolean>.
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_killed_and_hidden_from?(user)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless killed?
    return T.cast(Promise.resolve(true), Promise[T::Boolean]) unless user
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) if user.site_admin?

    T.must(repository).async_adminable_by?(user).then do |adminable|
      !adminable
    end
  end
end
