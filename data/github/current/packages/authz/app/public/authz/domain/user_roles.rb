# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class UserRoles < GH::Domain::Base
      ActorTypeToIds = T.type_alias { T::Hash[String, T::Array[Integer]] }

      DEFAULT_BATCH_SIZE = 1000
      DISTRIBUTION_TIME_STAT = "authz.domain.user_roles.call"

      ALL_ORG_CONDITION  = T.let(UserRoleCondition::Target::AllOrgs.serialize, String)
      SOME_ORG_CONDITION = T.let(UserRoleCondition::Target::SomeOrgs.serialize, String)

      # Internal: Initialize a new UserRoles domain object.
      #
      # This constructor sets up the UserRoles domain object with an initial query state.
      # The @current_query instance variable is initialized with a base ActiveRecord::Relation
      # that selects all UserRole records. This provides a starting point for query chaining
      # in the various builder methods throughout this class.
      #
      # Returns nothing.
      sig { void }
      def initialize
        super
        @current_query = T.let(UserRole.all, T.nilable(ActiveRecord::Relation))
      end

      # Internal: Determines if business-level query should be enabled for a target organization.
      #
      # This method checks if the organization is part of a business with the enterprise_teams_esm
      # feature enabled. When enabled, queries will include roles assigned at the business level
      # in addition to organization-level roles.
      #
      # target - The Organization to check for business query eligibility
      #
      # Returns a Boolean indicating whether business queries should be included
      sig do
        params(
          target: Organization
        ).returns(T::Boolean)
      end
      def business_query_enabled?(target)
        !!target.async_business.then do |business|
          business&.erp_feature_enabled?(:enterprise_teams_esm)
        end.sync
      end

      # Public: Fetch all-repository roles for a given actor type and actor IDs for a given target.
      #
      # target     - The target organization for the role check.
      # actor_type - The type of the actor (e.g., User, Team).
      # actor_ids  - An array of actor IDs to check for roles.
      #
      # Returns a hash mapping actor types to an array of actor IDs that have roles.
      sig do
        params(
          target: Organization,
          actor_type: String,
          actor_ids: T::Array[Integer],
          permission: RepoPermissionType
        ).returns(T::Hash[String, T::Array[Integer]])
      end
      def role_assignments_with_repo_fgp_for_actors(target:, actor_type:, actor_ids:, permission: Authz::Domain::RepoPermissionType::READ) # rubocop:disable Metrics/MethodLength
        return {} if actor_ids.empty?

        business_query_enabled = business_query_enabled?(target)
        tags = ["esm_enabled:#{business_query_enabled}", "method:#{T.must(__method__)}"]

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: tags) do
          results = T.let([], T::Array[[Integer, String]])

          actor_ids.in_groups_of(DEFAULT_BATCH_SIZE, false) do |actor_ids_group|
            # Handle business target conditions if feature is enabled
            query = if business_query_enabled
              where_target_org(target: target)
              .or(where_target_org_business(target: target))
              .and(where_actors(actor_type: actor_type, actor_ids: actor_ids_group))
            else
              where_target_org(target: target)
              .and(where_actors(actor_type: actor_type, actor_ids: actor_ids_group))
            end

            # Join with roles and role_permissions for base repo permission
            query = with_base_role_permission_action(query, permission: permission)
            results.concat(query.distinct.pluck(:actor_id, :actor_type))
          end

          map_actor_type_to_actor_ids(results)
        end
      end

      # Public: Fetches all role assignments with associated base role permissions for a target organization.
      #
      # This method retrieves all user role assignments for a given target organization, optionally filtered
      # by specific permission levels. If the target is part of a business with the enterprise_teams_esm
      # feature enabled, it will include roles assigned at both the business and organization levels.
      #
      # target     - The Organization for which to retrieve role assignments.
      # permission - Optional Symbol specifying the permission level to filter by (:all, :read, :write, :admin).
      #              Defaults to :read if not specified.
      # batch_size - Optional Integer specifying the batch size for the query.
      #              Defaults to 1000 if not specified.
      #
      # Returns a Hash mapping actor types (e.g., "User", "Team") to Arrays of actor IDs that have the
      # specified permission level roles for the target organization.
      #
      # Examples:
      #   # Get all actors with read permissions for an organization
      #   batch_role_assignments_with_base_role_for_target(target: organization)
      #   # Get all actors with admin permissions for an organization
      #   batch_role_assignments_with_base_role_for_target(target: organization, permission: :admin)
      sig do
        params(
          target: Organization,
          permission: RepoPermissionType,
          batch_size: Integer
        ).returns(T::Hash[String, T::Array[Integer]])
      end
      def batch_role_assignments_with_base_role_for_target(target:, permission: Authz::Domain::RepoPermissionType::READ, batch_size: DEFAULT_BATCH_SIZE) # rubocop:disable Metrics/MethodLength
        business_query_enabled = business_query_enabled?(target)
        tags = ["esm_enabled:#{business_query_enabled}", "method:#{T.must(__method__)}"]

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: tags) do
          # Handle business target conditions if feature is enabled
          query = if business_query_enabled
            where_target_org(target: target)
            .or(where_target_org_business(target: target))
          else
            where_target_org(target: target)
          end

          # Join with roles and role_permissions for base repo permission
          query = with_base_role_permission_action(query, permission: permission)

          results = []
          query.distinct.select(:actor_id, :actor_type).in_batches(of: batch_size) do |batch|
            results.concat(batch.pluck(:actor_id, :actor_type))
          end

          map_actor_type_to_actor_ids(results)
        end
      end

      # Public: Fetches all role assignments by ID with the target organization.
      #
      # This method retrieves all user role assignments for a given target organization, filtered
      # by specific role ids. If the target is part of a business with the enterprise_teams_esm
      # feature enabled, it will include roles assigned at both the business and organization levels.
      #
      # target      - The Organization for which to retrieve role assignments.
      # role_ids    - The Array of Integer role IDs to filter by.
      # actor_types - Optional Array of Strings specifying the actor types to filter by (e.g., ["User", "Team"]).
      # batch_size  - Optional Integer specifying the batch size for the query.
      #               Defaults to 1000 if not specified.
      #
      # Returns a Hash mapping actor types (e.g., "User", "Team") to Arrays of actor IDs that have the
      # specified permission level roles for the target organization.
      #
      # Examples:
      #
      #   batch_role_assignments_with_role_ids_for_target(target: organization, role_ids: [1, 2, 3])
      #   # => { "User" => [1, 2], "Team" => [4] }
      #
      sig do
        params(
          target: Organization,
          role_ids: T::Array[Integer],
          actor_types: T::Array[String],
          batch_size: Integer
        ).returns(ActorTypeToIds)
      end
      def batch_role_assignments_with_role_ids_for_target(target:, role_ids:, actor_types: [], batch_size: DEFAULT_BATCH_SIZE) # rubocop:disable Metrics/MethodLength
        return {} if role_ids.empty?

        business_query_enabled = business_query_enabled?(target)
        tags = ["esm_enabled:#{business_query_enabled}", "method:#{T.must(__method__)}"]

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: tags) do
          @current_query = UserRole.where(role_id: role_ids)
          @current_query = @current_query.where(actor_type: actor_types) unless actor_types.empty?

          # Handle business target conditions if feature is enabled
          query = if business_query_enabled
            where_target_org(target: target)
            .or(where_target_org_business(target: target))
          else
            where_target_org(target: target)
          end

          results = []

          query.distinct.select(:actor_id, :actor_type).in_batches(of: batch_size) do |batch|
            results.concat(batch.pluck(:actor_id, :actor_type))
          end

          map_actor_type_to_actor_ids(results)
        end
      end

      # Efficiently retrieves the mapping of permission actions to organization IDs for given actors.
      #
      # This method determines which permission actions (such as :read, :view_dependabot_alerts, etc.)
      # are granted to specific actors (users, teams, etc.) across multiple organizations. It loads
      # organizations and their associated businesses, then queries for all relevant role assignments
      # in a single batched query to avoid N+1 performance issues.
      #
      # The method supports business-level roles and conditions, including both "all_orgs" and "some_orgs"
      # business role conditions, and expands those to the appropriate organization IDs.
      #
      # target_ids - Array of Integer organization IDs to check for permissions.
      # actions    - Array of Symbol permission actions to filter by (e.g., [:read, :write]).
      # actor_type - String representing the actor type (e.g., "User", "Team").
      # actor_id   - Array of Integer actor IDs to check for roles.
      #
      # Returns an Array of Arrays, where each sub-array contains [action, org_id] for each permission
      # granted to the specified actors on the organizations.
      #
      # Example:
      #   actors_permissions_for_orgs(
      #     target_ids: [1, 2, 3],
      #     actions: [:read, :write],
      #     actor_type: "User",
      #     actor_id: [42, 99]
      #   )
      #   # => [["read", 1], ["write", 2], ...]
      sig do
        params(
          target_ids: T::Array[Integer],
          actions: T::Array[Symbol],
          actor_type: String,
          actor_id: T::Array[Integer]
        ).returns(T::Array[[String, Integer]])
      end
      def actors_permissions_for_orgs(target_ids:, actions:, actor_type:, actor_id:) # rubocop:disable Metrics/MethodLength
        # Remove any nil and duplicate values first
        target_ids = target_ids.compact.uniq
        return [] if target_ids.empty?

        # Use GitHub's existing async loading pattern - load organizations and their businesses
        organizations_with_businesses = Organization.includes(:business).batched_scope(:id, values: target_ids).to_a
        businesses = T.let(Set.new, T::Set[Business])

        organization_ids_by_business = organizations_with_businesses.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |org, hash|
          if (business = org.business)
            businesses << business
            hash[business.id] << org.id
          end
        end

        esm_enabled = businesses.any? { |business| business.erp_feature_enabled?(:enterprise_teams_esm) }

        actions_on_orgs = T.let([], T::Array[[String, Integer]])

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:#{esm_enabled}", "method:#{T.must(__method__)}"]) do
          organizations_with_businesses.in_groups_of(DEFAULT_BATCH_SIZE, false) do |group|
            role_permissions = batch_role_assignments_for_targets(
              organizations: group,
              permissions: actions,
              actor_type:,
              actor_id:,
            )

            actions_on_orgs.concat(
              role_permissions.in_batches(of: 5000).flat_map do |batch|
                batch.pluck(:action, :target_id, :target_type, :conditions_target, :conditions_target_ids).filter_map do |action, target_id, target_type, conditions_target, conditions_target_ids|
                  org_ids = []

                  if target_type == "Business"
                    if conditions_target == ALL_ORG_CONDITION
                      org_ids = organization_ids_by_business.fetch(target_id, Set.new)
                    elsif conditions_target == SOME_ORG_CONDITION
                      org_ids = conditions_target_ids
                    end
                  elsif target_type == "Organization"
                    org_ids = [target_id]
                  end

                  (org_ids & target_ids).map { |org_id| [action, org_id] } unless org_ids.empty?
                end
              end.flatten(1)
            )
          end

          actions_on_orgs
        end
      end

      # Public: Fetches organization IDs for which the user has been granted an all_repo_role grant
      # The user can get this grant directly or indirectly through a team or business team
      #
      # Orgs with indirect team grants are returned with or without the inclusion of the organization_ids parameter
      # Orgs with indirect business team grants are only returned with the inclusion of the organization_ids parameter
      # Currently business teams do not support unbounded queries
      #
      # user - The User for whom to check role grants.
      # fgp - The RepoPermissionType to check for (e.g., READ, WRITE, ADMIN).
      # organization_ids - Optional Array of Integer organization IDs to filter by
      #
      # 1. find org_ids the user has a direct all-repo role grant on
      # 2. get all the teams the user is part of
      #   a. get all business teams the user is part of if the organization_ids are included
      # 3. get all the org_ids for which the teams and biz teams have been granted an all_repo_role grant
      #   a. business team grants for all-repo roles are included under the `enterprise_teams_org_assignment` feature flag
      #   b. ESM grants for all-repo roles targeting the business are included under the `enterprise_teams_esm` feature flag
      # 4. combine orgs from 1 and 3
      sig do
        params(
          user: User,
          permission: RepoPermissionType,
          organization_ids: T::Array[Integer]
        ).returns(T::Array[Integer])
      end
      def org_ids_with_all_repo_role_grant_for_user(user:, permission:, organization_ids: [])
        return [] if user.organization?

        direct_ids = org_ids_with_direct_all_repo_role_grant(user:, organization_ids:, permission:)
        indirect_ids = org_ids_with_indirect_all_repo_role_grant(user:, organization_ids:, permission:)

        (direct_ids + indirect_ids).uniq
      end

      # Public: Retrieve ability actions for specific actors within a target organization.
      #
      # This method determines what repository-level ability actions (read, write, admin) are
      # available to a set of actors (users, teams, etc.) within the specified organization.
      # It queries the user_roles table to find role assignments for the given actors and
      # returns all repository permissions granted through those roles.
      #
      # The method supports business organization queries when the feature is enabled,
      # allowing it to check permissions across both regular organizations and their
      # associated business entities.
      #
      # target             - An Organization object representing the target organization to check permissions for
      # actor_types_to_ids - A Hash mapping actor types (String) to arrays of actor IDs (Array of Integer)
      #                      Example: { "User" => [123, 456], "Team" => [789] }
      #
      # Examples
      #
      #   # Get all repository actions available to specific users and teams
      #   domain.ability_actions_for_target_and_actors(
      #     target: organization,
      #     actor_types_to_ids: { "User" => [123, 456], "Team" => [789] }
      #   )
      #   # => [:read, :write]
      #
      #
      # Returns an Array of Symbols representing the repository ability actions that are
      #         available to at least one of the specified actors within the target organization.
      #         Returns an empty array if no actor_types_to_ids are provided or if none of
      #         the actors have any repository permissions.
      sig do
        params(
          target: Organization,
          actor_types_to_ids: ActorTypeToIds
        ).returns(T::Array[Symbol])
      end
      def ability_actions_for_target_and_actors(target:, actor_types_to_ids:) # rubocop:disable Metrics/MethodLength
        return [] if actor_types_to_ids.empty? || actor_types_to_ids.values.all?(&:empty?)

        business_query_enabled = business_query_enabled?(target)

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:#{business_query_enabled}", "method:#{T.must(__method__)}"]) do
          query = where_target_org(target: target)

          # Handle business target conditions if feature is enabled
          if business_query_enabled
            query = query.or(where_target_org_business(target: target))
          end

          # Specify actor_types and actor_ids
          query = query.and(where_actors_by_type_map(actor_type_to_ids: actor_types_to_ids))
          # Join with roles and role_permissions for base repo permission
          query = with_base_role_permission_action(query, permission: Authz::Domain::RepoPermissionType::ANY)

          results = query.distinct.pluck(:action)

          # Map action strings to symbols like :write, :read or :admin
          results.map { |action| Ability::ALL_REPO_ROLE_FGP_ABILITY[action] }.compact
        end
      end

      # Public: Check if any of the specified actors have been granted a repository role for a target organization.
      #
      # This method determines whether at least one of the provided actors (users, teams, etc.) has been
      # assigned a role that includes the specified repository permission level within the target organization.
      # It's designed for boolean checks where you need to know if permission exists, rather than retrieving
      # the full set of actors or their specific permissions.
      #
      # The method supports business organization queries when the enterprise_teams_esm feature is enabled,
      # allowing it to check permissions across both regular organizations and their associated business
      # entities. This is particularly useful for enterprise scenarios where teams may be granted roles
      # at the business level that apply to specific organizations.
      #
      # The method uses an optimized query that returns early with a boolean result rather than loading
      # full records, making it efficient for permission gate scenarios.
      #
      # target               - An Organization object representing the target organization to check permissions for
      # actor_type_to_ids    - A Hash mapping actor types (String) to arrays of actor IDs (Array<Integer>)
      #                        e.g., { "User" => [123, 456], "Team" => [789], "BusinessTeam" => [101] }
      # permission           - A RepoPermissionType enum value specifying the minimum permission level to check for
      #                        (defaults to ALL, which matches any repository permission)
      #
      # Examples
      #
      #   # Check if specific users and teams have read access to an organization
      #   domain.repo_role_granted_to_actors(
      #     target: organization,
      #     actor_type_to_ids: { "User" => [123, 456], "Team" => [789] },
      #     permission: Authz::Domain::RepoPermissionType::READ
      #   )
      #   # => true
      #
      #   # Check if a team has admin access
      #   domain.repo_role_granted_to_actors(
      #     target: organization,
      #     actor_type_to_ids: { "Team" => [789] },
      #     permission: Authz::Domain::RepoPermissionType::ADMIN
      #   )
      #   # => false
      #
      #   # Check if any actor has any repository permission
      #   domain.repo_role_granted_to_actors(
      #     target: organization,
      #     actor_type_to_ids: { "User" => [123], "Team" => [789], "BusinessTeam" => [101] },
      #     permission: Authz::Domain::RepoPermissionType::ANY
      #   )
      #   # => true
      #
      # Returns a Boolean indicating whether at least one of the specified actors has been granted
      #         a role with the specified permission level for the target organization. Returns false
      #         if no actor_type_to_ids are provided or if none of the actors have the required permission.
      sig do
        params(
          target: Organization,
          actor_types_to_ids: ActorTypeToIds,
          permission: RepoPermissionType
        ).returns(T::Boolean)
      end
      def repo_role_granted_to_any_actor?(target:, actor_types_to_ids:, permission: Authz::Domain::RepoPermissionType::ANY) # rubocop:disable Metrics/MethodLength
        return false if actor_types_to_ids.empty? || actor_types_to_ids.values.all?(&:empty?)

        business_query_enabled = business_query_enabled?(target)

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:#{business_query_enabled}", "method:#{T.must(__method__)}"]) do
          query = where_target_org(target: target)

          # Handle business target conditions if feature is enabled
          if business_query_enabled
            query = query.or(where_target_org_business(target: target))
          end

          # Specify actor_types and actor_ids
          query = query.and(where_actors_by_type_map(actor_type_to_ids: actor_types_to_ids))

          # Join roles and role_permissions for base repo permission
          query = with_base_role_permission_action(query, permission: permission)

          results = query.exists?
        end
      end

      # Public: Find all actors granted a specific role (or base role) on a
      # target repository.
      sig { params(target_id: Integer, role: Role).returns(ActorTypeToIds) }
      def actors_granted_role_on_target_repo(target_id:, role:)
        query = build_query
          .where(target_id: target_id, target_type: "Repository")
          .joins(:role)
          .where("roles.id = :role_id OR roles.base_role_id = :role_id", role_id: role.id)

        results = []

        query.distinct.select(:actor_id, :actor_type).in_batches(of: DEFAULT_BATCH_SIZE) do |batch|
          results.concat(batch.pluck(:actor_id, :actor_type))
        end

        map_actor_type_to_actor_ids(results)
      end

      # Public: Find 'base extended' roles assignments for the given actors
      # within the context of a set of organizations and businesses.
      #
      # Examples
      #
      #     domain.base_extended_role_assignments_for(
      #       actor_type_to_ids: { "User" => [1, 2, 3] },
      #       org_ids: [10, 20],
      #       business_ids: [30]
      #     )
      #     # => [#<UserRole:0x00007763b4e81180 id: 165, ...>]
      #
      # Returns an array of interface UserRole objects.
      sig do
        params(
          actor_type_to_ids: ActorTypeToIds,
          org_ids: T::Array[Integer],
          business_ids: T::Array[Integer]
        ).returns(T::Array[IUserRole])
      end
      def base_extended_role_assignments_for(actor_type_to_ids:, org_ids:, business_ids:)
        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:#{business_ids.any?}", "method:#{T.must(__method__)}"]) do
          org_and_business_conditions = arel_org_and_business_targets_with_conditions_sql_literal(org_ids, business_ids)

          actor_type_to_ids.flat_map do |actor_type, actor_ids|
            build_query
              .eager_load(:role)
              .and(where_actors(actor_type:, actor_ids:))
              .where.not(role: { base_role: nil }) # all repo roles has a non-nil base_role which is a system repo role
              .where(
                # looking either for preset all repo role, custom org role, or custom business role.
                "(role.owner_type IS NULL AND role.owner_id IS NULL) OR (role.owner_type = :org_type AND role.owner_id IN (:org_ids)) OR (role.owner_type = :business_type AND role.owner_id IN (:target_business_ids))",
                { org_type: "Organization", org_ids: org_ids, business_type: "Business", target_business_ids: business_ids }
              ).where(org_and_business_conditions).to_a
          end
        end
      end

      # Public: Find all teams (Team and BusinessTeam) with specific permissions in given organizations
      #
      # This method executes an optimized query to find all teams that have been granted specific
      # permissions (actions) within the provided orgs/business. It checks both direct role permissions
      # and inherited base role permissions to ensure comprehensive coverage.
      #
      # if the role is granted at the business level and has the all_orgs permission, every org ID in the input
      # will be returned with the team and action, and if the role is granted at the business level
      # with the some_orgs permission, only the orgs that match the conditions will be returned.
      #
      # The query uses a CTE for better performance when dealing with
      # multiple organizations and filters results to only include teams with the specified actions.
      #
      # organization_ids - Array of Integer organization IDs to search within
      # actions         - Array of Symbol permission actions to filter by (e.g., [:read, :write, :admin])
      # business_id      - Optional business ID to filter by. If provided, the query will also
      #                   consider this business, its BusinessTeams, and any all_orgs or some_orgs conditions which apply to it.
      #
      # Returns a Hash mapping organization IDs to arrays of team permission data, where each
      #         team permission entry is an array containing [actor_type, actor_id, action].
      #
      # Examples:
      #   # Find teams with read and write permissions in specific organizations
      #   get_permissible_team_roles_for_organizations(
      #     organization_ids: [1, 2, 3],
      #     actions: [:view_secret_scanning_alerts, :read_code_scanning]
      #   )
      #   # => { 1 => [["Team", 123, :read]], 2 => [["Team", 456, :write], ["BusinessTeam", 789, :read]] }
      #
      #   # Find teams with admin permissions
      #   get_permissible_team_roles_for_organizations(
      #     organization_ids: [1],
      #     actions: [:read_code_scanning]
      #   )
      #   # => { 1 => [["Team", 123, :admin], ["BusinessTeam", 456, :admin]] }
      sig do
        params(
          organization_ids: T::Array[Integer],
          actions: T::Array[Symbol],
          business_id: T.nilable(Integer),
        ).returns(T::Hash[Integer, T::Array[T::Array[T.any(String, Integer, Symbol)]]])
      end
      def get_permissible_team_roles_for_organizations(organization_ids:, actions:, business_id: nil) # rubocop:disable Metrics/MethodLength
        return {} if organization_ids.empty? || actions.empty?

        business_teams_enabled = false
        esm_enabled = false

        # Verify every organization_id is present in the business
        if business_id.present?
          business_org_map = Orgs.domain.group_organization_ids_by_business(organization_ids)

          if business_org_map[business_id].nil? || T.must(business_org_map[business_id]).empty?
            raise ArgumentError, "Business ID #{business_id} does not include any of the provided organization IDs."
          end

          # compare every value in organization_ids with the business_org_map[business_id], and report on any missing orgs
          missing_orgs = organization_ids - T.must(business_org_map[business_id])
          unless missing_orgs.empty?
            raise ArgumentError, "Business ID #{business_id} does not include the following organization IDs: #{missing_orgs.join(', ')}"
          end

          business = Business.find(business_id)
          esm_enabled = business.erp_feature_enabled?(:enterprise_teams_esm)
          business_teams_enabled = business.enterprise_teams_org_roles_supported?
        end

        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:#{esm_enabled}", "business_teams_enabled:#{business_teams_enabled}", "method:#{T.must(__method__)}"]) do
          action_strings = actions.map(&:to_s)
          team_types = %w[Team]
          team_types << "BusinessTeam" if business_teams_enabled
          grouped_results = T.let({}, T::Hash[Integer, T::Set[T::Array[T.any(String, Integer, Symbol)]]])

          organization_ids.each_slice(DEFAULT_BATCH_SIZE) do |batch_org_ids|
            batch_org_ids_set = batch_org_ids.to_set
            filtered_user_roles = UserRole
              .select(:target_type, :target_id, :actor_type, :actor_id, :role_id)
              .select("case when target_type <> 'Business' then NULL
                            when conditions_target = 'some_orgs' then conditions_target_ids->>'$'
                            when conditions_target = 'all_orgs' then 'all_orgs'
                            end as business_targets") # the first statement is to avoid fetching the json unnecessarily when the target_type is not Business
              .where(actor_type: team_types)
              .where(target_type: "Organization", target_id: batch_org_ids)

            if esm_enabled
              filtered_user_roles = filtered_user_roles.or(UserRole
                .where(actor_type: team_types) # activerecord will de-duplicate these with the above.
                .where(target_type: "Business", target_id: business_id)
                .where("conditions_target = 'all_orgs' OR (conditions_target = 'some_orgs' AND JSON_OVERLAPS(conditions_target_ids, ?))", batch_org_ids.to_json)
              )
            end

            query = UserRole
              .with(filtered_user_roles: filtered_user_roles)
              .from("filtered_user_roles") # start from the CTE
              .joins("INNER JOIN roles ON roles.id = filtered_user_roles.role_id")
              .joins(ActiveRecord::Base.sanitize_sql_array([
                "LEFT JOIN role_permissions ON roles.id = role_permissions.role_id AND role_permissions.action IN (?)",
                action_strings
              ]))
              .joins("LEFT JOIN roles AS base_roles ON base_roles.id = roles.base_role_id")
              .joins(ActiveRecord::Base.sanitize_sql_array([
                "LEFT JOIN role_permissions AS base_role_permissions ON base_role_permissions.role_id = base_roles.id AND base_role_permissions.action IN (?)",
                action_strings
              ]))
              .select(
                "filtered_user_roles.target_type",
                "filtered_user_roles.target_id",
                "filtered_user_roles.actor_type",
                "filtered_user_roles.actor_id",
                "filtered_user_roles.business_targets",
                "role_permissions.action as role_permission_action",
                "base_role_permissions.action as base_permission_action"
              )
              .where("COALESCE(role_permissions.action, base_role_permissions.action) IS NOT NULL")
              .distinct
              .order("1, 2, 3, 4, 5, 6, 7") # Add consistent ordering for pagination
              .annotate("cross-schema-domain-query-exempted")

            # Execute the query with internal pagination to handle large result sets
            # Use manual batching with limit/offset to avoid ActiveRecord's built-in batching
            # which requires an id column that we don't have in this complex query
            offset_value = 0
            loop do
              batch_results = query.limit(DEFAULT_BATCH_SIZE).offset(offset_value).to_a
              break if batch_results.empty?

              batch_results.each do |result|
                # Access attributes using array indexing since we're using custom select
                target_id = result.attributes["target_id"].to_i
                actor_type = result.attributes["actor_type"]
                actor_id = result.attributes["actor_id"].to_i
                role_action = result.attributes["role_permission_action"]&.to_sym
                base_role_action = result.attributes["base_permission_action"]&.to_sym
                business_targets = result.attributes["business_targets"]

                # process the role and base role permissions separately, to retain situations
                # where the base role has an explicit permission that the role does not, e.g., where the
                # role has :read_secret_scanning_alerts but the base role has :repo_read
                # if the input asks for permissions for both of the above, we need to ensure both are returned
                role_actions_set = T.let(Set.new, T::Set[Symbol])
                role_actions_set.add(role_action) if role_action
                role_actions_set.add(base_role_action) if base_role_action

                # If no actions are found, skip to the next iteration, probably won't happen
                next if role_actions_set.empty?

                grouped_results[target_id] ||= T.let(Set.new, T::Set[T::Array[T.any(String, Integer, Symbol)]])
                role_actions_set.each do |role_action|
                  if !business_targets
                    # if this isn't a business target, we can just add the action for the target_id
                    T.must(grouped_results[target_id]).add([actor_type, actor_id, role_action])
                  else
                    # If business_targets is 'all_orgs', we add the action for all orgs in the batch since
                    # it has already been verified that all orgs in the batch are part of the business
                    if business_targets == "all_orgs"
                      batch_org_ids_set.each do |org_id|
                        grouped_results[org_id] ||= T.let(Set.new, T::Set[T::Array[T.any(String, Integer, Symbol)]])
                        T.must(grouped_results[org_id]).add([actor_type, actor_id, role_action])
                      end
                    else
                      # If business_targets is 'some_orgs', we add the action for each org in the conditions_target_ids
                      # which match our batch_org_ids
                      business_targets_ids = JSON.parse(business_targets)
                      business_targets_ids.each do |org_id|
                        if batch_org_ids_set.include?(org_id)
                          grouped_results[org_id] ||= T.let(Set.new, T::Set[T::Array[T.any(String, Integer, Symbol)]])
                          T.must(grouped_results[org_id]).add([actor_type, actor_id, role_action])
                        end
                      end
                    end
                  end
                end
              end

              # Break if we got fewer results than the batch size (indicating we've reached the end)
              break if batch_results.size < DEFAULT_BATCH_SIZE
              offset_value += DEFAULT_BATCH_SIZE
            end
          end

          # convert the set back to an array for each org_id
          grouped_results.reject { |_, v| v.empty? }.transform_values(&:to_a)
        end
      end

      private

      sig { params(organizations: T::Array[Organization]).returns(T.nilable(ActiveRecord::Relation)) }
      def build_business_query_with_preloaded_data(organizations)
        # Extract business mappings from preloaded organizations
        business_mappings = {}

        organizations.each do |org|
          business = org.business
          next unless business

          business_mappings[business.id] ||= []
          business_mappings[business.id] << org.id
        end

        return nil if business_mappings.empty?

        query_user_roles_from_business_mappings(business_mappings)
      end

      sig { params(business_mappings: T::Hash[Integer, T::Array[Integer]]).returns(T.nilable(ActiveRecord::Relation)) }
      def query_user_roles_from_business_mappings(business_mappings)
        conditions = business_mappings.map do |business_id, org_ids|
          [
            "(user_roles.target_type = 'Business' AND user_roles.target_id = ? AND " \
            "(user_roles.conditions_target = 'all_orgs' OR " \
            "(user_roles.conditions_target = 'some_orgs' AND JSON_OVERLAPS(user_roles.conditions_target_ids, ?))))",
            business_id, org_ids.to_json
          ]
        end
        sql_fragments = conditions.map { |cond| UserRole.sanitize_sql_array(cond) }
        build_query.where(sql_fragments.join(" OR "))
      end

      sig { returns(ActiveRecord::Relation) }
      def build_query
        @current_query || UserRole.all
      end

      sig do
        params(
          target: Organization,
        ).returns(ActiveRecord::Relation)
      end
      def where_target_org(target:)
        build_query.where(
          target_type: "Organization",
          target_id: target.id
        )
      end

      sig do
        params(
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def where_actors(actor_type:, actor_ids:)
        build_query.where(
          actor_type: actor_type,
          actor_id: actor_ids
        )
      end

      sig do
        params(
          target: Organization,
        ).returns(ActiveRecord::Relation)
      end
      def where_target_org_business(target:)
        business_id = T.must(target.business).id

        build_query.where(target_type: "Business", target_id: business_id)
        .where(
            "conditions_target = 'all_orgs' OR (conditions_target = 'some_orgs' AND CAST(? AS UNSIGNED) MEMBER OF (conditions_target_ids))",
            target.id
          )
      end

      sig do
        params(
          organizations: T::Array[Organization]
        ).returns(ActiveRecord::Relation)
      end
      def where_target_orgs_business(organizations:) # rubocop:disable Metrics/MethodLength
        # Find organizations where business_query_enabled? is true
        erp_enabled_organizations = organizations.select do |org|
          org.business&.erp_feature_enabled?(:enterprise_teams_esm)
        end.compact

        final_query = if erp_enabled_organizations.any?
          org_query = build_query.where("user_roles.target_type" => "Organization", "user_roles.target_id" => organizations.map(&:id))
          # Handle business targets efficiently using preloaded business data
          business_query = build_business_query_with_preloaded_data(erp_enabled_organizations)
          final_query = business_query.nil? ? org_query : org_query.or(business_query)
        else
          build_query.where(target_type: "Organization", target_id: organizations.map(&:id))
        end
        final_query
      end

      sig { params(query: ActiveRecord::Relation, permission: RepoPermissionType).returns(ActiveRecord::Relation) }
      def with_base_role_permission_action(query, permission: Authz::Domain::RepoPermissionType::READ)
        permissions = RepoPermissionType.for_level(permission)
        sanitized_sql = UserRole.sanitize_sql_array(["role_permissions.action IN (?)", permissions])

        query.
          joins("INNER JOIN roles ON user_roles.role_id = roles.id").
          joins("INNER JOIN role_permissions ON role_permissions.role_id = roles.base_role_id").
          where(sanitized_sql)
      end

      sig { params(query: ActiveRecord::Relation, permissions: T::Array[Symbol]).returns(ActiveRecord::Relation) }
      def with_role_permission_action(query, permissions)
        sanitized_sql = UserRole.sanitize_sql_array(["role_permissions.action IN (?)", permissions])

        query.
          joins("INNER JOIN roles ON user_roles.role_id = roles.id").
          joins("INNER JOIN role_permissions ON roles.id = role_permissions.role_id OR roles.base_role_id = role_permissions.role_id").
          where(sanitized_sql)
      end

      # Filters user roles by multiple actor types and their corresponding IDs using an efficient OR query.
      #
      # This method constructs a single SQL query that matches user roles where the actor_type and actor_id
      # combination matches any of the provided type-to-IDs mappings. It's designed to efficiently query
      # for roles across different actor types (e.g., Users, Teams) in a single database call.
      #
      # @param actor_type_to_ids [Hash<String, Array<Integer>>] A mapping of actor types to arrays of actor IDs
      #   Example: { "User" => [1, 2, 3], "Team" => [10, 20] }
      #
      # @return [ActiveRecord::Relation] A relation that will match user roles where:
      #   - (actor_type = 'User' AND actor_id IN (1, 2, 3)) OR
      #   - (actor_type = 'Team' AND actor_id IN (10, 20))
      #
      # @example
      #   user_roles.where_actors_by_type_map(actor_type_to_ids: { "User" => [1, 2], "Team" => [10] })
      #   # Returns roles for Users 1,2 and Team 10
      #
      # Returns an empty relation if:
      # - The input hash is empty
      # - All actor_ids arrays are empty
      sig do
        params(
          actor_type_to_ids: ActorTypeToIds
        ).returns(ActiveRecord::Relation)
      end
      def where_actors_by_type_map(actor_type_to_ids:)
        return build_query.none if actor_type_to_ids.empty?

        queries = actor_type_to_ids.filter_map do |actor_type, actor_ids|
          next if actor_ids.blank?
          build_query.where(actor_type: actor_type, actor_id: actor_ids)
        end

        return build_query.none if queries.empty?

        queries.reduce { |result, rel| result.or(rel) }
      end

      sig { params(rows: T::Array[[Integer, String]]).returns(T::Hash[String, T::Array[Integer]]) }
      def map_actor_type_to_actor_ids(rows)
        rows.each_with_object({}) do |(actor_id, actor_type), map|
          map[actor_type] ||= []
          map[actor_type] << actor_id
        end
      end

      sig do
        params(
          organizations: T::Array[Organization],
          permissions: T::Array[Symbol],
          actor_type: String,
          actor_id: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def batch_role_assignments_for_targets(organizations:, permissions:, actor_type:, actor_id:)
        final_query = where_target_orgs_business(organizations:)
        final_query = with_role_permission_action(final_query, permissions)
        final_query = final_query.and(where_actors(actor_type: actor_type, actor_ids: actor_id))
        final_query
      end

      # Fetch organization IDs for which the user has been directly granted a role with the base FGP
      sig do
        params(
          user: User,
          permission: RepoPermissionType,
          organization_ids: T::Array[Integer],
        ).returns(T::Array[Integer])
      end
      def org_ids_with_direct_all_repo_role_grant(user:, permission:, organization_ids:)
        direct_scope = where_actors(actor_type: "User", actor_ids: [user.id]).where(target_type: "Organization")
        direct_scope = with_base_role_permission_action(direct_scope, permission:)
        direct_scope = direct_scope.batched_scope(:target_id, values: organization_ids) unless organization_ids.empty?
        direct_scope.pluck(:target_id)
      end

      # Fetch organization IDs for which the user has been granted an all_repo_role grant via teams or business teams
      sig do
        params(
          user: User,
          permission: RepoPermissionType,
          organization_ids: T::Array[Integer],
        ).returns(T::Array[Integer])
      end
      def org_ids_with_indirect_all_repo_role_grant(user:, permission:, organization_ids:)  # rubocop:disable Metrics/MethodLength
        GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:true", "method:#{T.must(__method__)}"]) do
          # Org IDs grouped by business ID {business_id_1: [org_id_1, org_id_2], business_id_2: [org_id_3]}
          organization_ids_by_business = Orgs::Domain.new.group_organization_ids_by_business(organization_ids)

          # Find all team IDs for the user
          # To avoid large queries, only filter teams by organization_id if there is a single org https://github.com/github/github/pull/362936
          organization_id = organization_ids.first if organization_ids.length == 1
          # Returns user teams filtered by a single organization_id or all teams if organzation_id is nil
          team_ids = Orgs.domain.teams.team_ids_for_user(user, organization_id: organization_id)
          # Only returns biz teams if there are organization_ids
          # We don't support unbounded business team queries
          biz_team_ids = Orgs.domain.teams.business_team_ids_for_multiple(user_id: user.id, business_ids: organization_ids_by_business.keys)
          return [] unless team_ids.any? || biz_team_ids.any?

          # Find all user roles for team actor types on an organization target
          actor_type_to_ids = { "Team": team_ids, "BusinessTeam": biz_team_ids }
          indirect_scope = where_actors_by_type_map(actor_type_to_ids:).where(target_type: "Organization")
          indirect_scope = with_base_role_permission_action(indirect_scope, permission:)
          indirect_scope = indirect_scope.where(target_id: organization_id) if organization_id.present?

          # We group the target org_ids by actor_type so we can filter out the business teams based on FF enablement
          # { "Team" => [org_id_1, org_id_2], "BusinessTeam" => [org_id_3] }
          org_arr_by_actor_type = indirect_scope
            .batched_scope(:actor_id, values: team_ids + biz_team_ids)
            .pluck(:actor_type, :target_id)
            .each_with_object({}) { |(actor_type, target_id), hash| (hash[actor_type] ||= []) << target_id }

          # Org IDs on which the user has an indirect all-repo role grant via the business
          # [org_id_1, org_id_2, org_id_3]
          org_ids_assigned_arr_via_business = org_ids_with_indirect_all_repo_role_grant_on_business(user:, permission:, organization_ids_by_business:, team_ids: biz_team_ids)

          # Get organization IDs for which the ERP features are enabled
          # This will return a hash where keys are feature flags and values are arrays of organization IDs they are enabled for
          # { enterprise_teams_esm: [org_id_1, org_id_2], enterprise_teams_org_assignment: [org_id_3, org_id_4] }
          org_ids_by_feature = erp_enabled_org_ids(organization_ids_by_business:)

          # Filter results based on FF enablement for the businesses:
          # 1. For org targets of team assignments, we filter the results by organization_ids if present
          #   a. if organization_ids are empty, we return the unfiltered/unbounded list
          # 2. For business team assignments, we find the intersection of the org target for the role, organization_ids and the orgs enabled for the feature
          #   a. Org targets of a business team assignment are included if the :enterprise_teams_org_assignment feature is enabled
          #   b. Orgs targeted via a business condition are included if the :enterprise_teams_esm feature is enabled
          org_ids_for_team = org_arr_by_actor_type.fetch("Team", [])
          org_ids_for_team &= organization_ids if organization_ids.any?
          org_ids_for_team +
            (org_arr_by_actor_type.fetch("BusinessTeam", []) & org_ids_by_feature.fetch(:enterprise_teams_org_assignment)) +
            (org_ids_assigned_arr_via_business & org_ids_by_feature.fetch(:enterprise_teams_esm))
        end
      end

      # Fetch organization IDs for which the user has been granted an all_repo_role grant on the enterprise through a business team
      # This is used for the enterprise_teams_esm feature flag
      sig do
        params(
          user: User,
          permission: RepoPermissionType,
          organization_ids_by_business: T::Hash[Integer, T::Array[Integer]],
          team_ids: T::Array[Integer]
        ).returns(T::Array[Integer])
      end
      def org_ids_with_indirect_all_repo_role_grant_on_business(user:, permission:, organization_ids_by_business:, team_ids:)
        # the orgs in organization_ids_by_business are not yet filtered by ERP FF
        indirect_scope = where_actors_by_type_map(actor_type_to_ids: { "BusinessTeam": team_ids })
          .where(target_type: "Business", target_id: organization_ids_by_business.keys)
          .where.not(conditions: nil)

        indirect_scope = with_base_role_permission_action(indirect_scope, permission:)
        businesses_with_conditions = indirect_scope
          .batched_scope(:actor_id, values: team_ids)
          .pluck(:target_id, :conditions)
          .each_with_object({}) { |(business_id, condition), hash| (hash[business_id] ||= []) << UserRoleCondition.from_hash(condition) }

        # We coerce the query results to get a list of organization IDs that have this role via a business target
        # This represents all orgs in the businesses assigned this role via the business teams
        target_orgs_from_user_roles_on_business(businesses_with_conditions:, organization_ids_by_business:)
      end

      # Returns the organization IDs grouped by business ID for the provided organization IDs
      # This method is used to optimize the retrieval of organization IDs with ERP features enabled
      #
      # It returns a hash where the keys are the feature flag names and the values are enabled organization IDs.
      # {
      #  enterprise_teams_esm: [org_id_1, org_id_2, org_id_3],
      #  enterprise_teams_org_assignment: [org_id_1, org_id_2, org_id_3]
      # }
      sig do
        params(
          organization_ids_by_business: T::Hash[Integer, T::Array[Integer]]
        ).returns(T::Hash[Symbol, T::Array[Integer]])
      end
      def erp_enabled_org_ids(organization_ids_by_business:)
        # we are doing a single business lookup for multiple ERP features as an optimization
        erp_features = %i(enterprise_teams_esm enterprise_teams_org_assignment)
        result = { enterprise_teams_esm: [], enterprise_teams_org_assignment: [] }

        # filter business orgs by feature flag
        Business.where(id: organization_ids_by_business.keys).each do |business|
          erp_features.each do |feature|
            result[feature] += organization_ids_by_business[business.id] if business.erp_feature_enabled?(feature)
          end
        end
        result
      end

      # Internal: Extract target organization IDs from user roles on business targets.
      # Used in org_ids_with_indirect_all_repo_role_grant to determine if ESM role grants access
      # to organizations under a business.
      #
      # businesses_with_conditions - A hash where keys are business IDs and values are arrays of conditions
      #                              that specify the target organizations.
      # Example: { business_id => [ { "target" => "all_orgs" }, { "target" => "some_orgs", "target_ids" => [org_id1, org_id2] } ] }
      # organization_ids_by_business - A hash mapping business IDs to arrays of organization IDs.
      # Example: { business_id => [org_id1, org_id2] }
      sig do
        params(
          businesses_with_conditions: T::Hash[Integer, T::Array[UserRoleCondition]],
          organization_ids_by_business: T::Hash[Integer, T::Array[Integer]]
        ).returns(T::Array[Integer])
      end
      def target_orgs_from_user_roles_on_business(businesses_with_conditions:, organization_ids_by_business:)
        businesses_with_conditions.each_with_object([]) do |(business_id, conditions), org_ids|
          organizations_ids_from_business = organization_ids_by_business.fetch(business_id, [])

          if conditions.any? { |condition| condition.target == UserRoleCondition::Target::AllOrgs }
            org_ids.concat(organizations_ids_from_business)
          elsif conditions.any? { |condition| condition.target == UserRoleCondition::Target::SomeOrgs }
            # if the role does not exist with the "all_orgs" condition, we check for "some_orgs"
            # and add the org_ids from each condition
            target_ids_collection = conditions.flat_map(&:target_ids).compact

            org_ids.concat(organizations_ids_from_business.intersection(target_ids_collection))
          end
          org_ids
        end.compact.uniq
      end

      sig { params(org_ids: T::Array[Integer], business_ids: T::Array[Integer]).returns(Arel::Nodes::SqlLiteral) }
      def arel_org_and_business_targets_with_conditions_sql_literal(org_ids, business_ids)
        sql = <<~SQL
          (
            (
              user_roles.target_type = 'Organization' AND user_roles.target_id IN (?)
            )
            OR
            (
              (
                user_roles.target_type = 'Business' AND user_roles.target_id IN (?)
              )
              AND
              (
                user_roles.conditions_target = 'all_orgs'
                OR
                (
                  user_roles.conditions_target = 'some_orgs'
                  AND JSON_OVERLAPS(user_roles.conditions_target_ids, ?)
                )
              )
            )
          )
        SQL

        Arel.sql(UserRole.sanitize_sql_array([sql, org_ids, business_ids, org_ids.to_json]))
      end
    end
  end
end
