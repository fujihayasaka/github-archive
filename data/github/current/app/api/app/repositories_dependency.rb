# typed: strict
# frozen_string_literal: true

module Api::App::RepositoriesDependency
  extend T::Helpers

  requires_ancestor { Api::App::ErrorDependency }

  # Ensures the Repository has a non-empty git repo.
  #
  # repo - Repository to check.
  #
  # Halts the request if the Repository is empty.
  sig { params(repo: Repository).void }
  def ensure_repo_content!(repo)
    deliver_error!(409, message: "Git Repository is empty.") if repo.empty?
  end

  # Ensures the repository is writable. Currently used to stop updates to
  # a repository and related models during a migration or when the repository
  # is archived, or when a repository has exceeded its size quota.
  #
  # repo - Repository to check.
  # ignore_archived - If true, archived repository checks will be ignored.
  #
  # Halts the request if the repository is locked for migration or archived.
  sig { params(repo: Repository, ignore_archived: T::Boolean).void }
  def ensure_repo_writable!(repo, ignore_archived: false)
    if repo.private?
      control_access :get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true
    end

    deliver_error_if_locked_on_migration! repo
    deliver_error_if_archived! repo, ignore_archived
    deliver_error_if_over_quota! repo
    deliver_error_if_locked!(repo)
  end

  # Delivers an error if the repo is locked
  sig { params(repo: Repository).void }
  def deliver_error_if_locked!(repo)
    if repo.locked?
      deliver_error! 403, message: "Repository has been locked."
    end
  end

  # Delivers an error if the repo is locked during a migration.
  #
  # repo - Repository to check.
  #
  # Halts the request if the repository is locked for migration.
  sig { params(repo: Repository).void }
  def deliver_error_if_locked_on_migration!(repo)
    if repo.locked_on_migration?
      deliver_error! 403, message: "Repository has been locked for migration."
    end
  end

  # Delivers an error if the repo is archived.
  #
  # repo - Repository to check.
  # ignore_archived - If true, archived repository checks will be ignored.
  #
  # Halts the request if the repository is archived.
  sig { params(repo: Repository, ignore_archived: T::Boolean).void }
  def deliver_error_if_archived!(repo, ignore_archived = false)
    if !ignore_archived && repo.archived?
      deliver_error! 403, message: "Repository was archived so is read-only."
    end
  end

  # Delivers an error if the repo is above its lock size quota.  Record
  # a metric if it is above either the lock or warn size quota.
  #
  # repo - Repository to check.
  sig { params(repo: Repository).void }
  def deliver_error_if_over_quota!(repo)
    return unless GitHub.repository_quotas_enabled?
    if repo.above_lock_quota?
      GitHub.dogstats.increment("git.api.quota", tags: ["type:lock"])
      deliver_error! 403, message: "Repository is above its size quota."
    elsif repo.above_warn_quota?
      GitHub.dogstats.increment("git.api.quota", tags: ["type:warn"])
    end
  end

  # Delivers an error for a disabled repository.
  #
  # repo - Repository which is disabled.
  sig { params(repo: Repository).void }
  def deliver_disabled_repo_error!(repo)
    control_access :get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true

    halt deliver(:disabled_repository_hash, repo, status: 403)
  end

  # Delivers an error for a blocked repository.
  #
  # repo - Repository which is blocked.
  sig { params(repo: Repository).void }
  def deliver_blocked_repo_error!(repo)
    control_access :get_repo, resource: repo, allow_integrations: true, allow_user_via_granular_actor: true

    halt deliver(:disabled_repository_hash, repo, status: 451)
  end
end
