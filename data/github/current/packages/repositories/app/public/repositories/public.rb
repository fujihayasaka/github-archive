# typed: strict
# frozen_string_literal: true

module Repositories
  module Public
    extend self
    extend T::Sig

    include Kernel

    # Returns an active repository with the given id, or nil
    sig { params(id: T.any(Integer, String)).returns(T.nilable(::Repository)) }
    def find_active(id)
      ::Repository.find_by(id: id, active: true)
    end

    # Returns an active repository with the given id, or raises
    sig { params(id: T.any(Integer, String)).returns(::Repository) }
    def find_active!(id)
      ::Repository.find_by!(id: id, active: true)
    end

    sig { params(id: Integer).returns(T::Boolean) }
    def is_active?(id)
      Repository.exists?(id: id, active: true)
    end

    # returns a soft-deleted Repository, or nil
    sig { params(id: Integer).returns(T.nilable(::Repository)) }
    def find_deleted(id)
      Repository.find_by(id: id, active: nil)
    end

    # returns a soft-deleted Repository, or raises
    sig { params(id: T.any(Integer, String)).returns(::Repository) }
    def find_deleted!(id)
      ::Repository.find_by!(id: id, active: nil)
    end

    # returns true if there exists a soft-deleted repository
    sig { params(id: Integer).returns(T::Boolean) }
    def is_deleted?(id)
      Repository.exists?(id: id, active: nil)
    end

    # Returns repo by id, either active or deleted
    sig { params(id: Integer).returns(T.nilable(::Repository)) }
    def get_active_or_deleted(id)
      ::Repository.find_by(id: id)
    end

    # The find an active and soft-deleted Repository with the given
    # id or raises `ActiveRecord::RecordNotFound`.
    #
    # Unless you really want to include soft-deleted repos, you should
    # use find_active! instead.
    sig { params(id: T.any(Integer, String)).returns(::Repository) }
    def get_active_or_deleted!(id)
      ::Repository.find(id)
    rescue TypeError, ArgumentError => e
      raise ActiveRecord::RecordNotFound, e.message
    end

    sig { params(owner_id: Integer).returns(ActiveRecord::Relation) }
    def active_owned_by(owner_id)
      Repository.where(owner_id: owner_id, active: true)
    end

    sig { params(owner_id: Integer).returns(ActiveRecord::Relation) }
    def deleted_owned_by(owner_id)
      Repository.where(owner_id: owner_id, active: nil)
    end

    sig { params(query_size: Integer, end_date: Time).returns(ActiveRecord::Relation) }
    def find_old_deleted_repos(query_size, end_date)
      Repository.deleted_before(end_date).order("updated_at ASC").limit(query_size)
    end

    sig { params(query_size: Integer).returns(ActiveRecord::Relation) }
    def failed_creations(query_size)
      Repository.deleted
        .joins("INNER JOIN repository_orchestrations on repositories.id = repository_orchestrations.repository_id")
        .merge(CreateRepositoryOrchestration.where(state: %w[failed skipped abandoned]))
        .where(deleted_at: nil)
        .limit(query_size)
    end

    # Public: Fetch the repository public models for the given ids
    sig { params(repo_ids: T::Array[Integer]).returns(ActiveRecord::Relation) }
    def load_repositories(*repo_ids)
      Repository.where(id: repo_ids, active: true)
    end

    sig { params(repo_ids: T::Array[Integer]).returns(ActiveRecord::Relation) }
    def where_public(repo_ids)
      Repository.where(id: repo_ids).public_scope.active
    end

    sig { params(repo_ids: T::Array[Integer]).returns(ActiveRecord::Relation) }
    def where_private(repo_ids)
      Repository.where(id: repo_ids).private_scope.active
    end

    sig { returns(ActiveRecord::Relation) }
    def none
      Repository.none
    end

    # Public: Return both active and deleted Repositories for an Organization.
    #
    # org - The Organization
    #
    # Returns Array of Repository.
    sig { params(org: ::Organization).returns(T::Array[Repository]) }
    def active_and_deleted_for_org(org)
      T.unsafe(Repository).where(organization_id: org.id).find_in_batches.to_a.flatten
    end

    # Public: Return ids of both active and deleted Repositories for an Organization.
    #
    # org - The Organization
    #
    # Returns Array of Integer.
    sig { params(org: ::Organization).returns(T::Array[Integer]) }
    def active_and_deleted_for_org_ids(org)
      T.unsafe(Repository).where(organization_id: org.id).pluck(:id).to_a.flatten
    end

    # Is the argument a repository owned by an enterprise?
    sig { params(repo: T.untyped).returns(T::Boolean) }
    def enterprise_owned?(repo)
      case repo
      when ::Repository
        !!repo.owner&.business
      else
        false
      end
    end

    sig { params(repo: T.untyped).returns(T::Boolean) }
    def organization_owned?(repo)
      case repo
      when ::Repository
        owner = repo.owner
        if owner
          owner.organization?
        else
          false
        end
      else
        false
      end
    end

    # Check if the argument is an instance of class Repository.
    # Note that this pattern should be avoided and removed in future.
    sig { params(repo: T.untyped).returns(T::Boolean) }
    def unsafe_is_repository?(repo)
      repo.instance_of?(::Repository)
    end

    # Return the repo id of an argument that is Repository-like.  Right
    # now, this only works with `Repository` objects, but in the future
    # will handle instances of some wrapper class that allows API
    # consumers to avoid handling `::Repository` objects directly.
    sig { params(repository_like_thing: T.untyped).returns(T.nilable(Integer)) }
    def extract_id_attribute(repository_like_thing)
      case repository_like_thing
      when ::Repository
        repository_like_thing.id
      end
    end

    # Given a list of repository ids, return only those which are part of the
    # provided organization.
    sig { params(repo_ids: T::Array[Integer], organization_id: Integer).returns(ActiveRecord::Relation) }
    def filter_repo_ids_to_org(repo_ids:, organization_id:)
      Repository.where(organization_id: organization_id, id: repo_ids).active
    end

    # Public: Build a Repository relation that includes all repos that are accessible,
    # either by explicit association or implicitly due to public access.
    #
    # repository_ids            - The ids of repositories to filter.
    # associated_repository_ids - The ids of repositories that the viewer explicitly has access to.
    #
    # Returns a Repository relation
    sig do
      params(repository_ids: T::Array[Integer], associated_repository_ids: T::Array[Integer])
        .returns(ActiveRecord::Relation)
    end
    def accessible_repositories(repository_ids:, associated_repository_ids:)
      # After this, repository_ids will only be repos
      # that aren't directly associated with the viewer.
      # Could be inaccessible or public.
      repository_ids -= associated_repository_ids

      Repository.public_scope.where(id: repository_ids).or(Repository.where(id: associated_repository_ids)).active
    end

    sig do
      params(
        owner: T.any(Organization, User, Repository, RepositoryNetwork, Topic),
        viewer: T.nilable(User),
        permission: Platform::Authorization::Permission,
        unauthorized_viewer_organization_ids: T.nilable(T::Array[Integer]),
        repo_type: String
      )
        .returns(T.any(RepositoriesFinder, RepositoriesOrganizationFinder))
    end
    def finder_for(
      owner:,
      viewer:,
      permission:,
      unauthorized_viewer_organization_ids:,
      repo_type: RepositoriesFinder::REPO_TYPE_DEFAULT
    )
      if owner.is_a?(Organization)
        return RepositoriesOrganizationFinder.new(
          owner: owner,
          viewer: viewer,
          unauthorized_viewer_organization_ids: unauthorized_viewer_organization_ids,
          permission: PlatformPermissionSwitch.new(permission),
          repo_type: repo_type
        )
      end

      RepositoriesFinder.new(
        owner: owner,
        viewer: viewer,
        unauthorized_viewer_organization_ids: unauthorized_viewer_organization_ids,
        permission: permission,
        repo_type: repo_type
      )
    end

    # Public: Returns a batch of repositories for an organization that: private, active, and not archived.
    #
    # This exists for cases when you want to filter on organization_id, public, and active but not parent_id but also
    # want to order by ID. Since we currently only have the index_repos_on_organization_id_active_public_and_parent_id
    # it's more efficient to do two queries and UNION if most of the repos in the organization are not forks
    sig { params(org_id: Integer, batch_start_id: Integer, batch_size: Integer).returns(T::Array[Repository]) }
    def private_active_and_maintained_by_org(org_id:, batch_start_id: 0, batch_size: 100)
      scope = Repository
        .where(organization_id: org_id)
        .active
        .private_scope
        .not_archived_scope
        .where("id > ?", batch_start_id)
        .limit(batch_size)
        .order(:id)

      no_parent_scope = scope.where("parent_id IS NULL")
      parent_scope = scope.where("parent_id IS NOT NULL")

      inner_query = [no_parent_scope, parent_scope].map(&:to_sql)
        .map { |q| "(#{q})" }
        .join(" UNION ")
      Repository.from("(#{inner_query}) AS repositories")
        .limit(batch_size)
        .order(:id)
        .to_a
    end

    sig { params(id: T.any(T.nilable(Integer), T.nilable(String))).returns(T.nilable(::Business)) }
    def resolve_tenant(id:)
      ::Repository.find_by(id: id)&.resolve_tenant
    end

    extend GitHub::DomainIsolation::PackageBoundary
  end
end
