# typed: true
# frozen_string_literal: true

require "egress"

module Egress
  class AccessControl
    # Public: Checks to see if the current User has the proper OAuth scope to
    # access the given Repository.
    #
    # repo - Repository instance.
    # user - User instance.
    #
    # Returns true if the User has the right scopes, otherwise false.
    def self.oauth_allows_access?(user, repo)
      repo.public? ? scope?(user, "public_repo") : scope?(user, "repo")
    end

    # Public: Checks to see if the current User is allowed to access the given
    # Repository given the Repository's organization's approved OAuth
    # applications.
    #
    # user - User instance.
    # repo - Repository instance.
    #
    # Returns true if the User has permission, otherwise false.
    def self.oauth_application_policy_satisfied?(user, repo)
      org = repo.async_organization.sync
      return true unless org
      return true unless user.governed_by_oauth_application_policy?
      org.allows_oauth_application?(user.oauth_application)
    end

    def self.oauth_allows_status_access?(user, repo)
      scoped = scope?(user, "repo:status")
      scoped ||= scope?(user, "public_repo") if repo.public?
      scoped
    end

    def self.oauth_allows_deploy_access?(user, repo)
      scoped = scope?(user, "repo_deployment")
      scoped ||= scope?(user, "public_repo") if repo.public?
      scoped
    end

    def self.oauth_allows_invitation_access?(user, repo)
      scoped = scope?(user, "repo:invite")
      scoped ||= scope?(user, "public_repo") if repo.public?
      scoped
    end

    def self.oauth_allows_package_read_access?(user, repo)
      scoped = scope?(user, "read:packages") || scope?(user, "write:packages")
      scoped ||= scope?(user, "public_repo") if repo.public?
      scoped
    end

    def self.oauth_allows_security_events_access?(user, repo)
      scoped = scope?(user, "security_events")
      scoped ||= scope?(user, "public_repo") if repo.public?
      scoped
    end
  end
end
