# typed: strict
# frozen_string_literal: true

module Orgs
  class Domain
    class Teams < GH::Domain::Base

      # Finds a team by its ID.
      # Parameters: id (Integer): The team ID to look up
      # Returns: A team object if found, nil otherwise
      # Example: team = orgs_domain.teams.by_id(12345)
      sig { params(id: Integer).returns(T.nilable(ITeam)) }
      def by_id(id)
        return nil if id <= 0

        Team.find_by(id: id.to_i)
      end

      # Gets business team IDs that are assigned to a specific organization.
      # Parameters: organization_id (Integer): The organization ID to check
      # Returns: Array of business team IDs that have access to the organization
      # Example: team_ids = orgs_domain.teams.business_team_ids_for_assigned_orgs(organization_id: 987)
      sig { params(organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_for_assigned_orgs(organization_id:)
        return [] if organization_id <= 0

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        all_orgs_team_ids = BusinessTeam.where(business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id).pluck(:team_id)

        all_orgs_team_ids + selected_org_team_ids
      end

      # Gets business team IDs that a user has access to within a business.
      # Parameters:
      #   business_id (Integer): The business ID to check
      #   user_id (Integer): The user ID to check permissions for
      # Returns: Array of business team IDs the user has access to
      # Example: team_ids = orgs_domain.teams.business_team_ids_for(business_id: 123, user_id: 456)
      sig { params(business_id: Integer, user_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_for(business_id:, user_id:)
        return [] if business_id <= 0
        return [] if user_id <= 0

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        teams = BusinessTeam.where(business_id: business_id, id: team_ids).pluck(:id)

        teams
      end

      # Gets business team IDs within a business.
      # Parameters:
      #   business_id (Integer): The business ID to check
      #   organization_ids (Integer array): Optional: Only returns business teams assigned to these
      #   organizations.
      # Returns: Array of business team IDs
      # Example: team_ids = orgs_domain.teams.business_team_ids_for(business_id: 123, organization_ids: [456])
      sig { params(business_id: Integer, organization_ids: T.nilable(T::Array[Integer])).returns(T::Array[Integer]) }
      def all_business_team_ids_for(business_id:, organization_ids: nil)
        all_orgs_team_ids = BusinessTeam.where(business_id: business_id, organization_selection_type: :all).pluck(:id)
        # TODO: BusinessTeamOrgAssignment should have a business_id field
        organization_ids ||= Business.find_by(id: business_id)&.organization_ids || []
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_ids).pluck(:team_id)
        all_orgs_team_ids + selected_org_team_ids
      end

      # Gets business team IDs that a user has access to for a specific organization.
      # Parameters:
      #   user_id (Integer): The user ID to check permissions for
      #   organization_id (Integer): The organization ID to check
      # Returns: Array of business team IDs the user has access to for the organization
      # Example: team_ids = orgs_domain.teams.business_team_ids_with_assigned_orgs_for(user_id: 456, organization_id: 987)
      sig { params(user_id: Integer, organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_ids_with_assigned_orgs_for(user_id:, organization_id:)  # rubocop:disable Metrics/MethodLength
        return [] if organization_id <= 0
        return [] if user_id <= 0

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        all_orgs_team_ids = BusinessTeam.where(id: team_ids, business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id, team_id: team_ids).pluck(:team_id)

        all_orgs_team_ids + selected_org_team_ids
      end

      # Gets user IDs from a list that are members of business teams with access to the organization.
      # Parameters:
      #   user_ids (Array of Integer): List of user IDs to check
      #   organization_id (Integer): The organization ID to check
      # Returns: Array of user IDs that are members of business teams with access to the organization
      # Example: user_ids = orgs_domain.teams.business_team_user_ids(user_ids: [101, 202, 303], organization_id: 987)
      sig { params(user_ids: T::Array[Integer], organization_id: Integer).returns(T::Array[Integer]) }
      def business_team_user_ids(user_ids:, organization_id:)  # rubocop:disable Metrics/MethodLength
        return [] if organization_id <= 0
        return [] if user_ids.empty?

        # look up business_id for given org_id
        business_org_membership = Business::OrganizationMembership.find_by(organization_id: organization_id)
        return [] unless business_org_membership
        business_id = business_org_membership.business_id

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_ids).pluck(:subject_id)
        all_orgs_team_ids = BusinessTeam.where(id: team_ids, business_id: business_id, organization_selection_type: :all).pluck(:id)
        selected_org_team_ids = BusinessTeamOrgAssignment.where(organization_id: organization_id, team_id: team_ids).pluck(:team_id)
        actor_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", subject_id: all_orgs_team_ids + selected_org_team_ids, actor_id: user_ids).pluck(:actor_id)

        actor_ids
      end

      # Gets organization IDs that a user has access to through business teams.
      # Parameters:
      #   user_id (Integer): The user ID to check
      #   organizations (Array of Organization, optional): Limit to only these organizations
      # Returns: Array of Organization IDs the user has access to
      # Example: org_ids = orgs_domain.teams.business_team_org_ids_for_user(user_id: 456)
      sig do
        params(
          user_id: Integer,
          organizations: T.nilable(T::Array[Organization]),
        ).returns(T::Array[Integer])
      end
      def business_team_org_ids_for_user(user_id:, organizations: nil) # rubocop:disable Metrics/MethodLength
        return [] if user_id <= 0

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        team_ids = Ability.where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_id).pluck(:subject_id)
        all_orgs_team_biz_ids = BusinessTeam.where(id: team_ids, organization_selection_type: :all).pluck(:business_id)

        # We only want to only select businesses that have the erp flag enabled,
        # so we need to filter on the flag rather than return all of the business team associated businesses during rollout
        filtered_business_ids = Business.where(id: all_orgs_team_biz_ids).select { |biz| biz.erp_feature_enabled?(:enterprise_teams_org_assignment) }.pluck(:id)

        all_orgs_team_org_ids = Business::OrganizationMembership.where(business_id: filtered_business_ids).pluck(:organization_id)
        selected_org_ids = BusinessTeamOrgAssignment.where(team_id: team_ids).pluck(:organization_id)

        # Selected organizations also need to be filtered
        filtered_selected_org_ids = Organization.where(id: selected_org_ids).includes(:business).select do |org|
          org.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
        end.pluck(:id)

        all_biz_team_org_ids = all_orgs_team_org_ids | filtered_selected_org_ids
        if organizations.present? && organizations.any?
          all_biz_team_org_ids = organizations.map(&:id) & all_biz_team_org_ids
        end

        Organization.where(id: all_biz_team_org_ids).pluck(:id)
      end

      # Finds a team by slug in the context of an organization.
      # For enterprise teams, matching is done with both ent: prefix or not.
      # If both an org team and enterprise teams share the same slug without prefix, the org team is returned.
      # It's highly recommended to always access enterprise teams with the prefix, non prefixed is supported for compatiblity.
      # If returning an enterprise team, the organization context is set to the org passed from parameters.
      # Parameters:
      #   organization (IOrganization): The organization context
      #   team_slug (String): The team slug to look up
      # Returns: A team object if found, nil otherwise
      # Example: team = orgs_domain.teams.find_team_by_slug_with_organization_context(org, "engineering")
      sig { params(organization: IOrganization, team_slug: String).returns(T.nilable(ITeam)) }
      def find_team_by_slug_with_organization_context(organization, team_slug)
        team = find_team_in_organization(business_id: organization.business&.id, organization_id: T.must(organization.id), team_slug: team_slug)
        team.set_organization_context(organization) if team.is_a?(BusinessTeam) && organization.is_a?(Organization)
        team
      end

      # Finds a team in an organization by ID or slug.
      # Parameters:
      #   business_id (Integer, optional): Business ID for enterprise teams
      #   organization_id (Integer): The organization ID
      #   team_id (Integer, optional): Team ID to find
      #   team_slug (String, optional): Team slug to find
      # Returns: A team object if found, nil otherwise
      # Example: team = orgs_domain.teams.find_team_in_organization(business_id: 123, organization_id: 987, team_slug: "security")
      # rubocop:disable Metrics/MethodLength
      sig { params(business_id: T.nilable(Integer), organization_id: Integer, team_id: T.nilable(Integer), team_slug: T.nilable(String)).returns(T.nilable(ITeam)) }
      def find_team_in_organization(business_id:, organization_id:, team_id: nil, team_slug: nil) # rubocop:disable GitHub/DocumentationDomainMethod
        return nil if organization_id <= 0
        return nil if !team_id&.positive? && team_slug.to_s.empty?

        # Try regular team first
        team = if team_id&.positive?
          Team.find_by(id: team_id, organization_id: organization_id)
        else
          Team.find_by(slug: team_slug, organization_id: organization_id)
        end
        return team if team
        return nil if business_id.nil?

        # Try business team
        business_team = if team_id&.positive?
          BusinessTeam.find_by(id: team_id)
        else
          BusinessTeam.find_by(business_id: business_id, slug: BusinessTeam.to_model_slug(team_slug.to_s))
        end
        return nil unless business_team

        # Check if business team is associated with this org
        business_org_membership = Business::OrganizationMembership.find_by(
          organization_id: organization_id,
          business_id: business_id
        )
        return nil unless business_org_membership

        # Verify team has access to this org (either all orgs or specifically assigned)
        result = if business_team.organization_selection_type.to_sym == :all
          business_team
        else
          business_team if BusinessTeamOrgAssignment.exists?(
            team_id: business_team.id,
            organization_id: organization_id
          )
        end

        result
      end

      # Gets teams that have access to a repository.
      # Parameters:
      #   repo_id (Integer): The repository ID
      #   team_ids (Array of Integer, optional): List of team IDs to filter by
      # Returns: Array of team objects with access to the repository
      # Example: teams = orgs_domain.teams.teams_for_repo(repo_id: 555)
      sig { params(repo_id: Integer, team_ids: T.nilable(T::Array[Integer])).returns(T::Array[ITeam]) }
      def teams_for_repo(repo_id:, team_ids: nil)  # rubocop:disable GitHub/DocumentationDomainMethod
        return [] if repo_id <= 0

        # TODO: ensure these queries are batched to avoid unbounded queries
        # TODO: replace abilities query with dependency on the authz domain
        query = Ability.where(subject_type: "Repository", subject_id: repo_id)
                       .where(actor_type: %w(Team BusinessTeam))
        query = query.where(actor_id: team_ids) if team_ids&.any?

        # Get abilities grouped by actor type
        abilities = query.pluck(:actor_type, :actor_id).group_by(&:first)

        teams = []
        # Find Team records
        if abilities["Team"]
          team_ids = abilities["Team"].map(&:last)
          teams += Team.where(id: team_ids).to_a
        end

        # Find BusinessTeam records
        if abilities["BusinessTeam"]
          business_team_ids = abilities["BusinessTeam"].map(&:last)
          teams += BusinessTeam.where(id: business_team_ids).to_a
        end

        teams
      end

      # Gets teams for a set of organizations, optionally filtered by specific team IDs.
      # This method fetches both regular organization teams and business teams that match the criteria.
      #
      # Parameters:
      #   org_ids (Array of Integer): List of organization IDs to find teams for
      #   team_ids (Array of Integer, optional): List of team IDs to filter by
      #
      # Returns: Hash mapping team IDs to team objects (both Team and BusinessTeam instances)
      # Example: teams_by_id = orgs_domain.teams.team_ids_for_orgs(org_ids: [123, 456], team_ids: [789, 101])
      sig { params(org_ids: T::Array[Integer], team_ids: T.nilable(T::Array[Integer])).returns(T::Hash[Integer, ITeam]) }
      def team_ids_for_orgs(org_ids:, team_ids: nil)
        return {} if org_ids.empty?

        # Base query condition - either team_ids is nil (return all) or in the specified list
        team_condition = team_ids.nil? ? {} : { id: team_ids }

        # Query 1: Regular organization teams
        org_teams = Team.where(organization_id: org_ids).where(team_condition)

        # Find organizations with the feature enabled
        orgs_with_feature = Organization.where(id: org_ids).includes(:business)
        .select { |org| org.business&.erp_feature_enabled?(:enterprise_teams_org_roles) }

        # If no orgs have the feature enabled, only return organization teams
        return org_teams.index_by(&:id) if orgs_with_feature.empty?

        # Get IDs of orgs with the feature enabled
        orgs_with_feature_ids = orgs_with_feature.map(&:id)

        # Query 2: Business teams with org_assignment_all where the organization belongs to their business
        all_org_business_teams = BusinessTeam
          .joins(business: :organization_memberships)
          .where(business_organization_memberships: { organization_id: orgs_with_feature_ids })
          .where(organization_selection_type: BusinessTeam.organization_selection_types[:all])
          .where(team_condition)
          .distinct

        # Query 3: Business teams with selected organizations via assignments
        selected_org_business_teams = BusinessTeam.joins(:business_team_org_assignments)
          .where(business_team_org_assignments: { organization_id: orgs_with_feature_ids })
          .where(organization_selection_type: BusinessTeam.organization_selection_types[:selected])
          .where(team_condition)
          .distinct

        # Combine results and index by ID
        (org_teams + all_org_business_teams + selected_org_business_teams).index_by(&:id)
      end

      # TODO: BusinessTeam inheritance is not implemented yet,
      # so this method returns only the ids of the users that are direct members of the team.
      # Public: Returns a list of user ids for the given team ids.
      #
      # This method is used to fetch the user ids for the given team ids.
      # It uses a cache to avoid hitting the database multiple times.
      #
      # Parameters:
      #   team_ids (Array of Integer): List of business team IDs to check
      # Returns: Array of user IDs that are members of the specified business teams
      # Example: user_ids = orgs_domain.teams.user_ids_for_business_teams([101, 202])
      sig { params(team_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def user_ids_for_business_teams(team_ids)
        return [] if team_ids.empty?

        PermissionCache.fetch ["user_ids_for_business_teams", team_ids] do
          GitHub.instrument "user_ids_for_business_teams.dist" do

            sql_bindings = {
              direct: Ability.priorities[:direct],
              team_ids: team_ids,
            }

            sql = Arel.sql <<-SQL, **sql_bindings
              SELECT actor_id
              FROM   abilities ab
              WHERE  ab.actor_type   = 'User'
              AND    ab.subject_id  IN (:team_ids)
              AND    ab.subject_type = 'BusinessTeam'
              AND    ab.priority     = :direct
            SQL

            Ability.connection.select_values(sql).uniq.sort!
          end
        end
      end

      # Gets team IDs that specific users are direct members of.
      # This method returns a mapping of user IDs to arrays of team IDs (both regular Teams and BusinessTeams)
      # that the users have direct membership in.
      #
      # Parameters:
      #   user_ids (Array of Integer): List of user IDs to check team membership for
      #
      # Returns: Hash mapping user IDs to arrays of team IDs they are direct members of
      # Example: team_mapping = orgs_domain.teams.team_ids_by_actor_id_for(user_ids: [101, 202])
      # Returns: { 101 => [1, 2, 3], 202 => [4, 5] }
      sig { params(actor_type: String, actor_ids: T.untyped).returns(T::Hash[Integer, T::Array[Integer]]) }
      def team_ids_by_actor_id_for(actor_type:, actor_ids:)
        team_ids_by_actor_id = Hash.new { |h, k| h[k] = [] }
        ::Ability.distinct.where(
          actor_type: actor_type,
          actor_id: actor_ids,
          subject_type: [Team, BusinessTeam],
          priority: ::Ability.priorities[:direct],
        ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
          team_ids_by_actor_id[actor_id] << subject_id
        end

        team_ids_by_actor_id
      end


      # Gets organization IDs that users have access to through business teams.
      # Parameters: user_ids (Array of Integer): List of user IDs to check
      # Returns: Hash mapping user IDs to arrays of organization IDs they have access to
      # Example: user_orgs = orgs_domain.teams.business_team_org_ids_for_users(user_ids: [101, 202])
      # Returns: { 101 => [1, 2, 3], 202 => [2, 4] }
      sig { params(user_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
      def business_team_org_ids_for_users(user_ids:) # rubocop:disable Metrics/MethodLength
        user_ids.filter! { |id| id > 0 }
        return {} if user_ids.empty?

        # TODO: ensure these queries are batched to avoid unbounded queries

        abilities = Ability
          .where(subject_type: "BusinessTeam", actor_type: "User", actor_id: user_ids)
          .pluck(:subject_id, :actor_id)

        # { team_id => [user_id] }
        user_ids_by_team_id = abilities
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(team_id, actor_id), result|
            result[team_id] << actor_id
          end
        all_team_ids_for_users = user_ids_by_team_id.keys

        # { team_id => business_id }
        biz_id_by_team_id_where_all_orgs_selected = BusinessTeam
          .where(id: all_team_ids_for_users, organization_selection_type: :all)
          .pluck(:id, :business_id)
          .to_h

        # { business_id => [team_id] }
        team_ids_by_biz_id_where_all_orgs_selected = biz_id_by_team_id_where_all_orgs_selected.each_with_object({}) do |(key, value), result|
          (result[value] ||= []) << key
        end

        all_orgs_team_org_ids = Business
          .where(id: team_ids_by_biz_id_where_all_orgs_selected.keys)
          .joins(:organization_memberships)
          .pluck(:id, :organization_id)

        # { team_id => [org_id] }
        org_ids_by_team_id_where_all_orgs_selected = all_orgs_team_org_ids
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(business_id, org_id), result|
            team_ids = team_ids_by_biz_id_where_all_orgs_selected[business_id]
            team_ids.each do |team_id|
              result[team_id] << org_id
            end
          end

        selected_org_ids = BusinessTeamOrgAssignment
          .where(team_id: all_team_ids_for_users)
          .pluck(:team_id, :organization_id)

        # { team_id => [org_id] }
        org_ids_by_team_id_where_specific_orgs_selected = selected_org_ids
          .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(team_id, org_id), result|
            result[team_id] << org_id
          end

        # { user_id => [org_id] }
        result = abilities.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(team_id, user_id), results|
          org_ids = results[user_id] || []
          org_ids += org_ids_by_team_id_where_all_orgs_selected[team_id] || []
          org_ids += org_ids_by_team_id_where_specific_orgs_selected[team_id] || []
          results[user_id] = org_ids.uniq
        end

        result
      end

      # Returns a list of { user_id:, org_id: } for users with access to orgs via business teams.
      # Parameters:
      #   business_id: (Integer, required)
      #   user_ids: (Array<Integer>, optional) filter search to these user ids
      #   org_ids: (Array<Integer>, optional) filter search to these org ids
      #   correlation_id: (String, optional) for tracing
      # Returns: Array of hashes with user_id and org_id
      # Example: orgs_domain.teams.business_org_indirect_memberships(business_id: 123, user_ids: [456, 457], org_ids: [123, 789])
      # Returns: [{ user_id: 456, org_id: 789 }, { user_id: 457, org_id: 123 }]
      sig do
        params(
          business_id: Integer,
          user_ids: T.nilable(T::Enumerable[Integer]),
          org_ids: T.nilable(T::Enumerable[Integer]),
          correlation_id: T.nilable(String),
        ).returns(T::Set[T::Hash[Symbol, Integer]])
      end
      def business_org_indirect_memberships(business_id:, user_ids: nil, org_ids: nil, correlation_id: nil)
        result = Set.new
        return result if business_id <= 0

        # Get all business team ids for this business, grouped by selection type
        all_orgs_team_ids, selected_orgs_team_ids = distribution_time("business_org_indirect_memberships.teams_by_selection_type", correlation_id:) do
          team_ids_by_selection_type = BusinessTeam.where(business_id: business_id).pluck(:id, :organization_selection_type).group_by { |_, type| type }
          return result if team_ids_by_selection_type.empty?
          all_orgs_team_ids = team_ids_by_selection_type["all"]&.map(&:first) || []
          selected_orgs_team_ids = team_ids_by_selection_type["selected"]&.map(&:first) || []
          [all_orgs_team_ids, selected_orgs_team_ids]
        end

        # Find all user-team memberships (Ability)
        user_team_pairs = distribution_time("business_org_indirect_memberships.user_team_pairs", correlation_id:) do
          ability_scope = Ability.where(subject_type: "BusinessTeam", actor_type: "User", subject_id: all_orgs_team_ids + selected_orgs_team_ids)
          ability_scope = ability_scope.where(actor_id: user_ids) if user_ids
          ability_scope.pluck(:actor_id, :subject_id)
        end
        return result if user_team_pairs.empty?

        # For teams with organization_selection_type: :all, get all orgs in the business (optionally filtered)
        orgs_for_all_teams = distribution_time("business_org_indirect_memberships.orgs_for_all_teams", correlation_id:) do
          org_memberships = Business::OrganizationMembership.where(business_id: business_id)
          org_memberships = org_memberships.where(organization_id: org_ids) if org_ids
          org_memberships.pluck(:organization_id)
        end if all_orgs_team_ids.any?
        orgs_for_all_teams ||= []

        # Get org assignments for selected teams
        selected_orgs_by_team_id = distribution_time("business_org_indirect_memberships.selected_orgs_by_team_id", correlation_id:) do
          selected_orgs_assignments = BusinessTeamOrgAssignment.where(team_id: selected_orgs_team_ids)
          selected_orgs_assignments = selected_orgs_assignments.where(organization_id: org_ids) if org_ids
          selected_orgs_assignments.group_by(&:team_id).transform_values do |assignments|
            assignments.map(&:organization_id)
          end
        end

        # Build result: for each user-team, add { user_id, org_id } for all orgs that team grants
        distribution_time("business_org_indirect_memberships.build_result", correlation_id:) do
          user_team_pairs.each do |user_id, team_id|
            orgs = []
            orgs += orgs_for_all_teams if all_orgs_team_ids.include?(team_id)
            if selected_org_ids = selected_orgs_by_team_id[team_id]
              orgs += selected_org_ids
            end
            orgs.each do |org_id|
              result.add({ user_id: user_id, org_id: org_id })
            end
          end
        end

        result
      end

      # Get teams by IDs.
      # If an organization is passed, it sets the organization context for business teams if those business teams
      # are associated with the organization.
      # This otherwise doesn't check that the organization teams are associated with the organization.
      sig { params(ids: T::Array[Integer], organization: T.nilable(IOrganization)).returns(T::Array[ITeam]) }
      def teams_by_ids(ids, organization: nil)
        teams = Team.with_business_teams.where(id: ids)
        BusinessTeam.set_organization_context_for_business_teams(teams, organization) if organization.is_a?(Organization)
        teams.to_a
      end

      private

      sig { params(stat: String, correlation_id: T.nilable(String), block: T.proc.void).returns(T.untyped) }
      def distribution_time(stat, correlation_id: nil, &block)
        start = GitHub::Dogstats.monotonic_time
        GitHub.dogstats.distribution_time(stat, &block)
      ensure
        duration_ms = (GitHub::Dogstats.monotonic_time - start) * 1000
        GitHub.logger.info(stat, "gh.correlation_id": correlation_id, "gh.duration.ms": duration_ms)
      end
    end
  end
end
