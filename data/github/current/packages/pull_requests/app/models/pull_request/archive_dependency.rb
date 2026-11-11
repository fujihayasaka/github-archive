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

  # Public: Archive this pull request via PullRequests::Orchestrations::Archive.
  # The orchestration closes the PR, locks it, marks it as archived in KV store,
  # and reindexes it for search in a background job.
  #
  # actor - The User performing the archive.
  # issue - The issue corresponding to this pull request, used for closing and locking.
  #
  # Returns void.
  sig { params(actor: User, issue: T.untyped).void }
  def archive!(actor, issue)
    return if archived?
    raise PullRequest::Error, "Cannot archive a merged pull request" if merged?

    repo = T.must(repository)
    raise PullRequest::PermissionError unless archivable_by?(actor)

    orchestration = PullRequests::Orchestrations::Archive.create(
      repository: repo,
      pull_request: self,
      data: { actor_id: actor.id },
    )

    begin
      orchestration.execute!
    rescue Orchestration::ValidationError
      raise PullRequest::Error, orchestration.errors.full_messages.join(", ")
    end

    raise PullRequest::Error, orchestration.error_message if orchestration.failed?
  end

  # Public: Unarchive this pull request via PullRequests::Orchestrations::Unarchive.
  # Removes the archived flag from KV store and reindexes for search in a background job.
  # Does NOT reopen or unlock — admin can do that separately.
  #
  # actor - The User performing the unarchive.
  #
  # Returns void.
  sig { params(actor: User).void }
  def unarchive!(actor)
    return unless archived?
    raise PullRequest::Error, "Cannot unarchive a merged pull request" if merged?

    repo = T.must(repository)
    raise PullRequest::PermissionError unless unarchivable_by?(actor)

    orchestration = PullRequests::Orchestrations::Unarchive.create(
      repository: repo,
      pull_request: self,
      data: { actor_id: actor.id },
    )

    begin
      orchestration.execute!
    rescue Orchestration::ValidationError
      raise PullRequest::Error, orchestration.errors.full_messages.join(", ")
    end

    raise PullRequest::Error, orchestration.error_message if orchestration.failed?
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
    return false if merged?
    return true unless user

    !GitHub::DomainIsolation.within_domain_of(Repository) { repo.adminable_by?(user) }
  end

  # Public: Async version of archived_and_hidden_from? for use in Promise chains.
  #
  # user - The User viewing the PR (may be nil for anonymous).
  #
  # Returns Promise<Boolean>.
  sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
  def async_archived_and_hidden_from?(user)
    repo = T.must(repository)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless FeatureFlag.vexi.enabled?(:archive_pull_request, repo, default: false)
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) unless archived?
    return T.cast(Promise.resolve(false), Promise[T::Boolean]) if merged?
    return T.cast(Promise.resolve(true), Promise[T::Boolean]) unless user

    repo.async_adminable_by?(user).then do |adminable|
      !adminable
    end
  end

  # Public: Check if the given user has permission to archive this pull request.
  #
  # user - The User to check.
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def archivable_by?(user)
    return false unless user
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, T.must(repository), default: false)

    T.must(repository).adminable_by?(user)
  end

  # Public: Check if the given user has permission to unarchive this pull request.
  #
  # user - The User to check.
  #
  # Returns Boolean.
  sig { params(user: T.nilable(User)).returns(T::Boolean) }
  def unarchivable_by?(user)
    return false unless user
    return false unless FeatureFlag.vexi.enabled?(:archive_pull_request, T.must(repository), default: false)

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
