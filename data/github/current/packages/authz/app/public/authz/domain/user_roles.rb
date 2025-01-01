# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class UserRoles < GH::Domain::Base
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
          actor_ids: T::Array[Integer]
        ).returns(T::Hash[String, T::Array[Integer]])
      end
      def all_repo_roles_for_actor(target:, actor_type:, actor_ids:)
        return {} if actor_ids.empty?

        # Handle business target conditions if feature is enabled
        query = if target.business&.erp_feature_enabled?(:enterprise_teams_esm)
          where_target_business_or_org(target: target, actor_type: actor_type, actor_ids: actor_ids)
        else
          where_target_org(target: target, actor_type: actor_type, actor_ids: actor_ids)
        end

        # Join with roles and role_permissions for base repo permission
        query = with_base_role_repo_permission_action(query).distinct

        results = query.pluck(:actor_id, :actor_type)
        map_actor_type_to_actor_ids(results)
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
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def where_target_org(target:, actor_type:, actor_ids:)
        UserRole.where(
            actor_type: actor_type,
            actor_id: actor_ids,
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
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def where_target_business_or_org(target:, actor_type:, actor_ids:)
        business_id = T.must(target.business).id

        # Create organization condition query
        org_condition = { target_type: "Organization", target_id: target.id }
        org_query = where_target_org(target: target, actor_type: actor_type, actor_ids: actor_ids)

        # Create business condition query with the same actor constraints
        business_query = UserRole.where(target_type: "Business", target_id: business_id)
                                .where(actor_type: actor_type, actor_id: actor_ids)
                                .where(
                                  "conditions_target = 'all_orgs' OR (conditions_target = 'some_orgs' AND CAST(? AS UNSIGNED) MEMBER OF (conditions_target_ids))",
                                  target.id.to_s
                                )

        org_query.or(business_query)
      end

      sig { params(query: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def with_base_role_repo_permission_action(query)
        query
          .joins("INNER JOIN roles ON user_roles.role_id = roles.id")
          .joins("INNER JOIN role_permissions ON role_permissions.role_id = roles.base_role_id")
          .where("role_permissions.action IN ('read_repo', 'write_repo', 'admin_repo')")
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

      sig { params(query: ActiveRecord::Relation, permissions: T::Array[Symbol]).returns(ActiveRecord::Relation) }
      def with_role_permission_action(query, permissions)
        sanitized_sql = UserRole.sanitize_sql_array(["role_permissions.action IN (?)", permissions])

        query.
          joins("INNER JOIN roles ON user_roles.role_id = roles.id").
          joins("INNER JOIN role_permissions ON roles.id = role_permissions.role_id OR roles.base_role_id = role_permissions.role_id").
          where(sanitized_sql)
      end


    end
  end
end
