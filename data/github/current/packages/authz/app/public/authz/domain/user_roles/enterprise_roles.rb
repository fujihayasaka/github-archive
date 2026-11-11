# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class UserRoles < GH::Domain::Base
      # Internal: Module containing enterprise role-specific functionality.
      #
      # The module is included in UserRoles to provide enterprise functionality
      # while maintaining a clean separation of concerns between organization-level
      # and enterprise-level role queries.
      module EnterpriseRoles
        extend T::Helpers
        requires_ancestor { UserRoles }

        # Public: Fetches actor assignments for a specific user and enterprise role that can operate on an organization.
        #
        # This method retrieves actor assignments for a given user and enterprise role combination
        # that have permissions to operate on the specified organization. It includes both direct
        # assignments to the user and indirect assignments via business teams the user is a member of.
        #
        # user                - The User to check role assignments for.
        # enterprise_role     - The EnterpriseRole object to filter by.
        # org                 - The Organization that the roles should be able to operate on.
        #
        # Returns a Hash mapping actor types to arrays of actor IDs that have the enterprise role
        # and access to the organization for the specified user.
        #
        # Examples:
        #
        #   actor_assignments_for_user_and_enterprise_role_on_org(
        #     user: user,
        #     enterprise_role: enterprise_role,
        #     org: organization
        #   )
        #   # => { "User" => [123], "BusinessTeam" => [456, 789] }
        #
        #   # Returns empty hash if user has no matching roles on organization
        #   actor_assignments_for_user_and_enterprise_role_on_org(
        #     user: different_user,
        #     enterprise_role: enterprise_role,
        #     org: organization
        #   )
        #   # => {}
        #
        sig do
          params(
            user: User,
            enterprise_role: EnterpriseRole,
            org: Organization
          ).returns(ActorTypeToIds)
        end
        def actor_assignments_for_user_and_enterprise_role_on_org(user:, enterprise_role:, org:) # rubocop:disable Metrics/MethodLength
          return {} unless org.business.present?
          tags = ["method:#{Kernel.__method__}"]

          GitHub.dogstats.distribution_time(UserRoles::DISTRIBUTION_TIME_STAT, tags: tags) do
            business = T.must(org.business)
            base_query = where_target_business(target: business).where(role_id: enterprise_role.id)

            # Build actor type to IDs map for the specific user
            actor_type_to_ids = { "User" => [user.id] }
            team_ids = Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(
              user_id: user.id,
              organization_id: org.id
            )
            actor_type_to_ids["BusinessTeam"] = team_ids if team_ids.any?

            results = base_query.and(where_actors_by_type_map(actor_type_to_ids: actor_type_to_ids)).pluck(:actor_id, :actor_type)
            map_actor_type_to_actor_ids(results)
          end
        end

        # Public: Finds users and business teams directly assigned enterprise roles with access to an organization.
        #
        # This method retrieves all actors (users and business teams) that have been directly assigned
        # the specified enterprise roles and have access to the given organization. For users, this includes
        # direct role assignments. For business teams, this includes teams assigned the roles that are also
        # assigned to the specified organization.
        #
        # enterprise_role_ids - An Array of Integer IDs of the enterprise roles to check assignments for.
        # org                 - The Organization to check for access to.
        #
        # Returns a Hash mapping actor types to arrays of actor IDs that have the enterprise roles
        # and access to the organization.
        #
        # Examples:
        #
        #   actors_with_enterprise_roles_for_org(enterprise_role_ids: [42], org: organization)
        #   # => { "User" => [123, 456], "BusinessTeam" => [789] }
        #
        #   actors_with_enterprise_roles_for_org(enterprise_role_ids: [42, 43], org: organization)
        #   # => { "User" => [123, 456, 789], "BusinessTeam" => [111, 222] }
        #
        #   # Returns empty hash if no actors have the roles for this organization
        #   actors_with_enterprise_roles_for_org(enterprise_role_ids: [99], org: different_org)
        #   # => {}
        #
        sig do
          params(
            enterprise_role_ids: T::Array[Integer],
            org: Organization
          ).returns(ActorTypeToIds)
        end
        def actors_with_enterprise_roles_for_org(enterprise_role_ids:, org:) # rubocop:disable Metrics/MethodLength
          return {} if org.business.nil? || enterprise_role_ids.empty?
          tags = ["method:#{Kernel.__method__}"]

          GitHub.dogstats.distribution_time(UserRoles::DISTRIBUTION_TIME_STAT, tags: tags) do
            business = T.must(org.business)
            base_query = where_target_business(target: business).where(role_id: enterprise_role_ids)

            # Build actor type to IDs map for proper SQL generation with parentheses
            actor_type_to_ids = {}

            # Get direct user assignments - these apply to any org in the business
            user_ids = base_query.where(actor_type: "User").distinct.pluck(:actor_id)
            actor_type_to_ids["User"] = user_ids if user_ids.any?

            # Get business teams with this role that are assigned to this specific organization
            team_ids = Orgs.domain.teams.business_team_ids_for_assigned_orgs(organization_id: org.id)
            if team_ids.any?
              team_actor_ids = base_query.where(actor_type: "BusinessTeam", actor_id: team_ids).distinct.pluck(:actor_id)
              actor_type_to_ids["BusinessTeam"] = team_actor_ids if team_actor_ids.any?
            end

            actor_type_to_ids
          end
        end
      end
    end
  end
end
