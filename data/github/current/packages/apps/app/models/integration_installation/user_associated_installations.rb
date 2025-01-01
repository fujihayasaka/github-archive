# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class UserAssociatedInstallations
    include GitHub::Memoizer
    include Scientist

    ACTOR_TYPE = "IntegrationInstallation"
    BATCH_SIZE = 1_000

    def initialize(user:, repository_ids: nil, excluded_organization_ids: [])
      @user = user
      @repository_ids = repository_ids
      @excluded_organization_ids = excluded_organization_ids
    end

    def self.associated_installations(user:, repository_ids: nil, excluded_organization_ids: [])
      new(
        user: user,
        repository_ids: repository_ids,
        excluded_organization_ids: excluded_organization_ids
      ).associated_installations
    end

    def associated_installations
      GitHub.tracer.in_span("IntegrationInstallation::UserAssociatedInstallations.associated_installations", kind: :internal) do |_span|
        return none unless @user

        installation_ids_from_repos = associated_installation_ids_through_repository_access

        # Only return adminable installations if we couldn't find any through
        # repository access.
        return adminable_installations if installation_ids_from_repos.none?

        adminable_installations.or(IntegrationInstallation.where(id: installation_ids_from_repos))
      end
    end

    private

    # Internal: Queries for all IntegrationInstallation records for adminable
    # targets.
    #
    # Returns an ActiveRecordRelation.
    def adminable_installations
      IntegrationInstallation.where(target_type: "User", target_id: adminable_target_ids)
    end

    # Private: All of the targets the @user can admin.
    #
    # Returns an Array of Integers.
    memoize def adminable_target_ids
      [@user.id, *@user.owned_organization_ids] - @excluded_organization_ids
    end

    # Private: A list of targets we don't want to query when searching for
    # installations.
    #
    # Returns an Array of Integers.
    memoize def excluded_target_ids
      excluded_target_ids = []

      excluded_target_ids.push(*adminable_target_ids) if query_scoped_via_repository_ids?
      excluded_target_ids.push(*@excluded_organization_ids)

      excluded_target_ids.uniq
    end

    # Private: Find all IntegrationInstallations that are installed on the
    # repositories through their organizations.
    #
    # NOTE: This does not mean the installations have repository permissions,
    # only that there are installation(s) on the targets.
    #
    # repository_ids - The Array of Integers representing the
    #                  primary IDs of repositories
    #
    # Examples
    #
    #   > installations_with_target_ids_and_repo_ids(repository_ids: [1,2,3,4])
    #   => {
    #        6  => { target_id: 42, repository_ids: [1,2] },
    #        12 => { target_id: 42, repository_ids: [1]   },
    #        75 => { target_id: 37, repository_ids: [3]   }
    #      }
    #
    # Returns a Hash.
    def installations_grouped_with_target_id_and_repo_ids(repository_ids: [])
      repository_ids_grouped_by_target = repository_ids_grouped_by_target_id(
        repository_ids: repository_ids,
      )

      return {} if repository_ids_grouped_by_target.empty?
      target_ids = repository_ids_grouped_by_target.keys

      installations = IntegrationInstallation.where(
        target_type: "User", target_id: target_ids,
      ).select(:id, :target_id)

      return {} unless installations.exists?

      installations.to_a.each_with_object({}) do |installation, hash|
        hash[installation.id] = {
          target_id: installation.target_id,
          repository_ids: repository_ids_grouped_by_target[installation.target_id]
        }
      end
    end

    # Private: Find all IntegrationInstallations that are installed on
    # "all repositories".
    #
    # target_ids - The Array of Intergers representing the primary id
    #              of IntegrationInstallation targets.
    #
    # Returns an Array of Integers.
    def installations_installed_on_all_repositories(target_ids: [])
      return [] if target_ids.empty?

      ::Permissions::Service.actor_ids_granted_permission(
        actor_type: "IntegrationInstallation",
        subject_type: "#{Repository::Resources::ALL_ABILITY_TYPE_PREFIX}/metadata",
        subject_ids: target_ids,
        action: 0
      )
    end

    # Internal: Helper method to return an AR scope with no
    # IntegrationInstallation records.
    #
    # Returns an ActiveRecordRelation.
    def none
      IntegrationInstallation.none
    end

    # Private: Group the given list of repository ids by the target they belong
    # to.
    #
    # Examples
    #
    #   > repository_ids_grouped_by_target_id(repository_ids: [1,2,3,4])
    #   => { 42 => [1,2], 37 => [3] }
    #
    #   > excluded_target_ids
    #   => [37]
    #   > repository_ids_grouped_by_target_id(repository_ids: [1,2,3,4])
    #   => { 42 => [1,2] }
    #
    # Returns a Hash.
    def repository_ids_grouped_by_target_id(repository_ids: [])
      return {} if repository_ids.empty?

      repo_ids_by_target_id = Hash.new { |h, k| h[k] = [] }

      repository_ids.in_groups_of(BATCH_SIZE, false) do |assoc_repo_ids|
        scope = Repository.active.where(id: assoc_repo_ids)

        if excluded_target_ids.any?
          scope = scope.where.not(owner_id: excluded_target_ids)
        end

        scope.pluck(:id, :owner_id).each do |repo_id, owner_id|
          repo_ids_by_target_id[owner_id] << repo_id
        end
      end

      repo_ids_by_target_id
    end

    def repository_metadata_permissions_grouped(actor_ids: [], subject_ids: [])
      return {} if actor_ids.empty? || subject_ids.empty?

      Permission.where(
        actor_type: "IntegrationInstallation",
        actor_id: actor_ids,
        subject_id: subject_ids,
        subject_type: "#{Repository::Resources::ABILITY_TYPE_PREFIX}/metadata"
      ).group_by(&:actor_id).transform_values { |permissions| permissions.map(&:subject_id) }
    end

    def query_scoped_via_repository_ids?
      @repository_ids.nil? ? false : true
    end

    # Internal: Find all IntegrationInstallations a User has access to through
    # the repositories they have access to.
    #
    # Returns an Array of Integers.
    def associated_installation_ids_through_repository_access
      installations_with_target_ids_and_repo_ids = installations_grouped_with_target_id_and_repo_ids(
        repository_ids: user_associated_repository_ids
      )
      return [] if installations_with_target_ids_and_repo_ids.empty?
      # Find all installations that are installed on "all repositories".
      installation_ids_candidate = installations_installed_on_all_repositories(
        target_ids: installations_with_target_ids_and_repo_ids.map { |_, target_and_repo_ids| target_and_repo_ids[:target_id] }.uniq
      )

      # Don't try to query installations that are on "all repositories"
      installation_ids_candidate.each do |installation_id|
        installations_with_target_ids_and_repo_ids.delete(installation_id)
      end

      subject_ids = installations_with_target_ids_and_repo_ids.values.map { |target_and_repo_ids| target_and_repo_ids[:repository_ids] }.flatten.uniq
      installations_with_repositories = repository_metadata_permissions_grouped(
        actor_ids: installations_with_target_ids_and_repo_ids.keys,
        subject_ids: subject_ids,
      )

      # For all installations found, intersect the two sets of repositories to
      # see if there there if there is a match.
      installations_with_repositories.each_pair do |installation_id, repository_ids|
        next unless installations_with_target_ids_and_repo_ids.key?(installation_id)

        next unless repository_ids.intersect?(
          installations_with_target_ids_and_repo_ids[installation_id][:repository_ids]
        )

        installation_ids_candidate << installation_id
      end
      installation_ids_candidate
    end

    # Private: Find the @user's associated repository ids potentially scoped by
    # the caller via @repository_ids.
    #
    # Returns an Array of Integer Repository IDs.
    def user_associated_repository_ids
      including = [:direct, :indirect_via_membership, :indirect_via_business_team_org_association]

      if query_scoped_via_repository_ids?
        including.push(:owned, :indirect_via_adminship)
      end

      @user.associated_repository_ids(
        including: including,
        include_indirect_forks: false,
        repository_ids: @repository_ids
      )
    end
  end
end
