# typed: strict
# frozen_string_literal: true

module PullRequest::ArchiveDependency
  extend T::Helpers

  requires_ancestor { PullRequest }

  KV_KEY_PREFIX = "pull_requests/archived/pr"

  # Public: Check if this pull request is archived.
  #
  # Returns Boolean.
  sig { returns(T::Boolean) }
  def archived?
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, T.must(repository), default: false)
    archive_kv.exists(archive_key).value { false }
  end

  # Public: Archive this pull request.
  # Closes the PR, locks it, and marks it as archived in KV store.
  #
  # actor - The User performing the archive.
  # issue - The issue corresponding to this pull request, used for closing and locking
  #
  # Returns void.
  sig { params(actor: User, issue: T.untyped).void }
  def archive!(actor, issue)
    return if archived?

    repo = T.must(repository)
    raise PullRequest::PermissionError unless repo.adminable_by?(actor)

    # Close the PR if it's open
    close_success = Issues.domain.update_state(issue, Issues::State::Closed, actor)
    raise PullRequest::Error, "Failed to close pull request while archiving" unless close_success

    # Lock the conversation
    lock_success = Issues.domain.update_state(issue, Issues::State::Locked, actor)
    raise PullRequest::Error, "Failed to lock pull request while archiving" unless lock_success

    # Mark as archived in KV store (no expiration — permanent until unarchived)
    archive_kv.set(archive_key, "true")
  end

  # Public: Unarchive this pull request.
  # Removes the archived flag. Does NOT reopen or unlock — admin can do that separately.
  #
  # actor - The User performing the unarchive.
  #
  # Returns void.
  sig { params(actor: User).void }
  def unarchive!(actor)
    return unless archived?

    repo = T.must(repository)
    raise PullRequest::PermissionError unless repo.adminable_by?(actor)

    archive_kv.del(archive_key)
  end

  # Public: Returns true if this PR is archived and should be hidden from the given user.
  # Only repository admins can see archived PRs.
  #
  # user - The User viewing the PR (may be nil for anonymous).
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def archived_and_hidden_from?(user)
    repo = T.must(repository)
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, repo, default: false)
    return false unless archived?
    return true unless user

    !GitHub::DomainIsolation.within_domain_of(Repository) { repo.adminable_by?(user) }
  end

  # Public: Check if the given user can archive this pull request.
  #
  # user - The User to check.
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def archivable_by?(user)
    return false unless user
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, T.must(repository), default: false)
    return false if archived?

    T.must(repository).adminable_by?(user)
  end

  # Public: Check if the given user can unarchive this pull request.
  #
  # user - The User to check.
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def unarchivable_by?(user)
    return false unless user
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, T.must(repository), default: false)
    return false unless archived?

    T.must(repository).adminable_by?(user)
  end

  private

  sig { returns(String) }
  def archive_key
    "#{KV_KEY_PREFIX}#{id}"
  end

  sig { returns(GitHub::KV) }
  def archive_kv
    PullRequests::KV.for_repository(T.must(repository))
  end
end
