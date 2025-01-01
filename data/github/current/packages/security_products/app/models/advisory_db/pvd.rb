# typed: strict
# frozen_string_literal: true

module AdvisoryDB
  # Methods for interacting with the Private Vulnerability Disclosure (PVD)
  # feature of repository security advisories.
  class Pvd

    sig { params(repo: ::Repository, user: T.nilable(::User), check_spammy: T::Boolean).returns(T::Boolean) }
    def self.authorized?(repo:, user:, check_spammy: true)
      authorized_repo?(repo: repo) &&
        authorized_user?(repo: repo, user: user, check_spammy: check_spammy)
    end

    # A repo is considered authorized to use PVD if:
    #
    # - Repo is public
    # - Repo is opted in (will use feature flag for closed beta)
    # - Repo is not on GHES (via `advisories_enabled?`)
    # - Repo has the private_vulnerability_reporting setting enabled
    # Each of these checks is reflected in `private_vulnerability_reporting_enabled?`
    sig { params(repo: ::Repository).returns(T::Boolean) }
    def self.authorized_repo?(repo:)
      return false if repo.nil?

      repo.private_vulnerability_reporting_enabled? && !AdvisoryDB::Innersource.repo_authorized?(repo: repo)
    end

    sig { params(repo: ::Repository, user: ::User).returns(T::Boolean) }
    def self.user_blocked_by_interaction_limit?(repo:, user:)
      return false unless GitHub.interaction_limits_enabled?
      # if user is restricted in any way, they are not allowed to use PVD
      RepositoryInteractionAbility.restricted_by_limit?(:sockpuppet_disallowed, repo, user) ||
      RepositoryInteractionAbility.restricted_by_limit?(:collaborators_only, repo, user) ||
      RepositoryInteractionAbility.restricted_by_limit?(:contributors_only, repo, user)
    end

    # A user is considered authorized to use PVD if:
    #
    # - We are not on GHES (GHES does not support repo advisories)
    # - User is logged in
    # - User is not an EMU
    # - User can access (read) repo (implied)
    # - User is not on repo owner blocked user list
    # - User is allowed via repo moderator interaction limits
    # - User does not otherwise have access to maintainer workflow, unless they are an installation
    # - Optionally, verify user is not spammy too (some checks need to bypass this)
    sig { params(repo: ::Repository, user: T.nilable(::User), check_spammy: T::Boolean).returns(T::Boolean) }
    def self.authorized_user?(repo:, user:, check_spammy: true)
      installation = user.try(:installation)

      return false if GitHub.single_or_multi_tenant_enterprise? ||
        repo.nil? ||
        user.nil? ||
        user.is_enterprise_managed? ||
        repo.owner_blocking?(user) ||
        (repo.advisory_management_authorized_for?(user) && !installation) ||
        user_blocked_by_interaction_limit?(repo: repo, user: user)

      return false if user.spammy? && check_spammy

      true
    end
  end
end
