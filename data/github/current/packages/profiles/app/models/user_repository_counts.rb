# typed: true
# frozen_string_literal: true

class UserRepositoryCounts

  include Scientist

  attr_reader :user

  def initialize(user, **preloads)
    @user = user
    @public_repositories = preloads[:public_repositories]
    @private_repositories = preloads[:private_repositories]
    @owned_private_repositories = preloads[:owned_private_repositories]
    @public_gists = preloads[:public_gists]
    @private_gists = preloads[:private_gists]
  end

  # Public: Counts the total number of repositories a user has access to.
  #
  # Returns an Integer.
  def total_repositories
    @total_repositories ||= begin
      with_read(user) { user.all_repositories_count }
    end
  end

  # Public: Counts the number of public repositories a user has.
  #
  # Returns an Integer.
  def public_repositories
    @public_repositories ||= begin
      with_read(user) { user.repositories.public_scope.limit(Organization::MEGA_ORG_REPOS_THRESHOLD).count }
    end
  end

  # Public: Counts the number of private repositories a user has, including forks.
  #
  # Returns an Integer.
  def private_repositories
    @private_repositories ||= begin
      with_read(user) { user.repositories.private_scope.limit(Organization::MEGA_ORG_REPOS_THRESHOLD).count }
    end
  end

  # Public: Counts the number of private repositories actually under a user's account.
  #
  # Returns an Integer.
  def owned_private_repositories
    @owned_private_repositories ||= begin
      with_read(user) do
        Repositories.domain.total_active_count_by_owner(
          owner_id: user.id,
          visibility: Repositories::RepositoryVisibility::Private,
          locked: false,
          network_roots: true,
          limit: Organization::MEGA_ORG_REPOS_THRESHOLD
        )
      end
    end
  end

  # Public: Counts the number of internal repositories a user has access to or
  #         the number of repos with internal visibility belonging to the org.
  #
  # Returns an Integer.
  def internal_repositories
    @internal_repositories ||= begin
      with_read(user) { user.internal_repositories.limit(Organization::MEGA_ORG_REPOS_THRESHOLD).count }
    end
  end

  # Public: Counts the number of disabled repositories a user has access to or
  #         the number of disabled repos belonging to the org.
  #
  # Returns an Integer.
  def disabled_repositories
    @disabled_repositories ||= begin
      with_read(user) { user.repositories.where("disabled_at IS NOT NULL").limit(Organization::MEGA_ORG_REPOS_THRESHOLD).count }
    end
  end

  # Public: Counts the number of locked repositories a user has access to or
  #         the number of locked repos belonging to the org.
  #
  # Returns an Integer.
  def locked_repositories
    @locked_repositories ||= begin
      with_read(user) { user.repositories.locked_repos.limit(Organization::MEGA_ORG_REPOS_THRESHOLD).count }
    end
  end

  # Public: Counts the number of public gists owned by a user.
  #
  # Returns an Integer.
  def public_gists
    @public_gists ||= begin
      with_read(user) { user.public_gists.count }
    end
  end

  # Public: Counts the number of private gists owned by a user.
  #
  # Returns an Integer.
  def private_gists
    @private_gists ||= begin
      with_read(user) { user.private_gists.count }
    end
  end

  protected

  def with_read(user, &block)
    ActiveRecord::Base.connected_to(role: :reading) { yield }
  end
end
