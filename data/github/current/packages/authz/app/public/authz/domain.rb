# typed: strict
# frozen_string_literal: true

module Authz
  class Domain < GH::Domain::Base
    include SorbetTypes

    ############################################################
    # This file contains backports from https://github.com/github/github/pull/390167 as
    # packages/authz/app/public/authz/domain/user_roles.rb does not exist in this version of GHES.
    # See https://github.com/github/security-center/issues/6807
    ############################################################

    DEFAULT_BATCH_SIZE = 1000
    DISTRIBUTION_TIME_STAT = "authz.domain.user_roles.call"

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

    # Public: check if the actor is granted the provided permission against the subject
    # Returns an boolean indicating if access is allowed and if the check was indeterminate.
    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def check_allowed(actor, permission, subject)
      start_time = GitHub::Dogstats.monotonic_time
      if actor.can_have_granular_permissions?
        programmatic_actor_check_single(actor, permission, subject)
      else
        user_check_single(T.cast(actor, User), permission, subject)
      end
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("authz.domain.check_allowed", elapsed, tags: [
        "success:#{$!.nil?}",
        "permission:#{permission}",
        "actor_type:#{actor.class.name}",
        "subject_type:#{subject.class.name}"])
    end


    # Public: check if an actor is granted the provided permissions against a subject
    # Returns an T::Hash[Symbol, T::Boolean] mapping each permission to a boolean indicating if access is allowed
    sig do
      params(
        actor: Actor,
        permissions: T::Array[Symbol],
        subject: Subject)
      .returns(T::Hash[Symbol, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def check_multiple_permissions(actor, permissions, subject)
      start_time = GitHub::Dogstats.monotonic_time
      requests = permissions.uniq.map { |permission| Request.new(actor: actor, permission: permission, subject: subject) }

      results = if actor.can_have_granular_permissions?
        programmatic_actor_check_batch(requests)
      else
        user_check_batch(requests)
      end

      results.map do |request, is_allowed|
        [request.permission, is_allowed]
      end.to_h
    ensure
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution("authz.domain.check_multiple_permissions", elapsed, tags: [
        "success:#{$!.nil?}",
        "permission_count:#{permissions.count}",
        "actor_type:#{actor.class.name}",
        "subject_type:#{subject.class.name}"])
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

      actions_on_orgs = T.let([], T::Array[[String, Integer]])

      GitHub.dogstats.distribution_time(DISTRIBUTION_TIME_STAT, tags: ["esm_enabled:false", "method:#{T.must(__method__)}"]) do
        organizations_with_businesses.in_groups_of(DEFAULT_BATCH_SIZE, false) do |group|
          role_permissions = batch_role_assignments_for_targets(
            organizations: group,
            permissions: actions,
            actor_type:,
            actor_id:,
          )

          actions_on_orgs.concat(
            role_permissions.in_batches(of: 5000).flat_map do |batch|
              batch.pluck(:action, :target_id, :target_type).filter_map do |action, target_id, target_type|
                org_ids = []
                if target_type == "Organization"
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
          .where(actor_type: team_types)
          .where(target_type: "Organization", target_id: batch_org_ids)

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
            "role_permissions.action as role_permission_action",
            "base_role_permissions.action as base_permission_action"
          )
          .where("COALESCE(role_permissions.action, base_role_permissions.action) IS NOT NULL")
          .distinct
          .order("1, 2, 3, 4, 5, 6") # Add consistent ordering for pagination
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
              # if this isn't a business target, we can just add the action for the target_id
              T.must(grouped_results[target_id]).add([actor_type, actor_id, role_action])
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

    sig { returns(ActiveRecord::Relation) }
    def build_query
      @current_query || UserRole.all
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
      build_query.where(target_type: "Organization", target_id: organizations.map(&:id))
    end

    sig { params(query: ActiveRecord::Relation, permissions: T::Array[Symbol]).returns(ActiveRecord::Relation) }
    def with_role_permission_action(query, permissions)
      sanitized_sql = UserRole.sanitize_sql_array(["role_permissions.action IN (?)", permissions])

      query.
        joins("INNER JOIN roles ON user_roles.role_id = roles.id").
        joins("INNER JOIN role_permissions ON roles.id = role_permissions.role_id OR roles.base_role_id = role_permissions.role_id").
        where(sanitized_sql)
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
      type_parameters(:R)
      .params(
        span_name: String,
        block: T.proc.params(span: T.untyped).returns(T.type_parameter(:R))
      ).returns(T.type_parameter(:R))
    end
    def with_tracing_span(span_name, &block)
      GitHub.tracer.in_span("authz.domain.#{span_name}", kind: :internal) do |span|
        yield span
      end
    end

    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def programmatic_actor_check_single(actor, permission, subject)
      with_tracing_span("programmatic_actor_check_single") do |_span|
        request = Request.new(actor:, permission:, subject:)
        T.must(programmatic_actor_check_batch([request]).values.first)
      end
    end

    sig do
      params(requests: T::Array[Request])
      .returns(T::Hash[Request, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def programmatic_actor_check_batch(requests)
      with_tracing_span("programmatic_actor_check_batch") do |_span|
        assert_programmatic_access_configured(requests)

        requests.map do |req|
          check_method = req.fine_grained_permission.programmatic_access_check_for(req.subject)
          result = T.cast(check_method.call(req.actor), T::Boolean)
          [req, result]
        end.to_h
      end
    end

    sig { params(requests: T.any(T::Array[Request], Request)).void }
    def assert_programmatic_access_configured(requests)
      with_tracing_span("assert_programmatic_access_configured") do |_span|
        fgps = Array.wrap(requests).map(&:fine_grained_permission)
        unsupported = Array.wrap(fgps).reject { |fgp| fgp.supports_programmatic_access? }
        if unsupported.any?
          list_string = unsupported.map { |fgp| "'#{fgp.action}'" }.join(", ")
          raise ArgumentError.new("The following FGPs are not configured for programmatic access: #{list_string}")
        end
      end
    end

    sig do
      params(
        actor: Actor,
        permission: Symbol,
        subject: Subject)
      .returns(T::Boolean)
      .checked(:always).on_failure(:raise)
    end
    def user_check_single(actor, permission, subject)
      with_tracing_span("user_check_single") do |_span|
        request = Request.new(actor:, permission:, subject:)
        result = user_check_batch([request])
        T.must(result.values.first)
      end
    end

    sig do
      params(domain_requests: T::Array[Request])
      .returns(T::Hash[Request, T::Boolean])
      .checked(:always).on_failure(:raise)
    end
    def user_check_batch(domain_requests)
      with_tracing_span("user_check_batch") do |_span|
        authzd_req_to_domain_req = domain_requests.map { |domain_req| [domain_req.authzd_request_hash, domain_req] }.to_h
        authzd_requests = authzd_req_to_domain_req.keys
        batch_response = Permissions::Enforcer.batch_authorize(requests: authzd_requests)

        indeterminates = batch_response.responses.select { |result| result.indeterminate? }
        if indeterminates.any?
          messages = indeterminates.map { |result| "Reason: #{result.reason}\nError: #{result.error&.message}" }.join("\n")
          raise IndeterminateError.new("Indeterminate response(s) from authzd.\n#{messages}")
        end

        authzd_requests.map do |authzd_req|
          [T.must(authzd_req_to_domain_req[authzd_req]), batch_response[authzd_req].allow?]
        end.to_h
      end
    end
  end
end
