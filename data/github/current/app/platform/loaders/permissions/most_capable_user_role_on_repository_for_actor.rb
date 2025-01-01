# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class MostCapableUserRoleOnRepositoryForActor < Platform::Loader
        def self.load(actor:, repo:)
          # Note: we pass `actor` here instead of `actor_id` because for `Team`
          # instances we also need to be able to look up `id_and_ancestor_ids`
          # and prefer not to pass an `id` and look it back up inside of `fetch`
          self.for(actor.class).load([actor, repo])
        end

        def initialize(actor_class)
          @actor_class = actor_class
          @repo_owner_business_ids = T.let({}, T::Hash[Integer, Integer])
        end

        # entries is an Array of [actor (User, Team, BusinessTeam), Repository] that we're trying to look up
        # return is a Hash indexed by the entries with the most capable user_role as the value
        def fetch(entries)
          actors, repos = entries.transpose
          repos_by_id = repos.index_by(&:id)

          # Return early if we are requesting for a Business Team and none of the repos are enabled for the feature
          return {} if @actor_class == BusinessTeam && !enterprise_teams_org_roles_enabled_for_any_repo_business(repos_by_id)

          # Collect all relevant user roles for actors
          relevant_actors_by_actor_id = relevant_actors_by_actor_id_for(actors)
          direct_user_roles = UserRole.eager_load(:role).where(
            actor_type: @actor_class, actor_id: relevant_actors_by_actor_id.keys,
            target_type: Repository, target_id: repos_by_id.keys
          )

          # Collect all relevant user roles for teams actor is a part of
          relevant_actors_by_team_id = relevant_actors_by_team_id_for(actors, repos_by_id)

          # We need to cache this as it will run for each team in the orgs multiple times.
          if relevant_actors_by_team_id.any?
            direct_user_roles += fetch_user_role_assignments_for_team(repos_by_id, relevant_actors_by_team_id)
          end

          # Choose the most capable Repository Role per actor/repo
          # Hash indexed by entry ([actor, repo] pair) pointing to a UserRole
          results_by_entry = select_most_capable_roles(direct_user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id, repos_by_id)

          # Find most capable all repo roles for [actor.id, org.id] pairs
          most_capable_all_repo_user_roles = fetch_most_capable_all_repo_user_role(repos_by_id, relevant_actors_by_actor_id, relevant_actors_by_team_id)

          # For each [actor, repo] pair in results_by_entry compare against [actor, repo.owner]
          # (or [actor, repo.owner.business]) and select the all repo role if more capable.
          entries.each do |key|
            actor, repo = key
            org_id = repo.owner_id
            next if org_id.nil?
            most_capable_repo_user_role = results_by_entry[key]

            most_capable_all_repo_user_role = compare_user_roles(
              most_capable_all_repo_user_roles[[actor.id, "Organization", org_id]],
              most_capable_all_repo_user_roles[[actor.id, "Business", @repo_owner_business_ids[org_id]]],
              actor
            )

            next if most_capable_all_repo_user_role.nil?
            results_by_entry[key] = compare_user_roles(most_capable_repo_user_role, most_capable_all_repo_user_role, actor)
          end
          results_by_entry
        end

        private

        # Get repository IDs where enterprise_teams_org_roles is enabled
        def repos_with_enterprise_teams_org_roles_enabled(repos_by_id)
          # Cache for previously checked businesses to avoid redundant feature flag checks
          @checked_businesses ||= {}

          repos_by_id.each_with_object([]) do |(id, repo), result|
            business = repo.owner&.business
            next unless business

            business_id = business.id
            # Check if we've already verified this business
            if !@checked_businesses.key?(business_id)
              @checked_businesses[business_id] = business.erp_feature_enabled?(:enterprise_teams_org_roles)
              @repo_owner_business_ids[repo.owner_id] = business_id if business.erp_feature_enabled?(:enterprise_teams_esm)
            end

            # Add repo ID to result if the feature is enabled for this business
            if @checked_businesses[business_id]
              result << id
            end
          end
        end

        # Is enterprise teams org roles enabled for any repo in the list?
        def enterprise_teams_org_roles_enabled_for_any_repo_business(repos_by_id)
          return false if repos_by_id.empty?
          repos_with_enterprise_teams_org_roles_enabled(repos_by_id).any?
        end

        def fetch_user_role_assignments_for_team(repos_by_id, relevant_actors_by_team_id)
          # NOTE(assyadh): check the permission cache for the repo role team keys'
          cache_key = most_capable_repo_role_for_team_cache_key(relevant_actors_by_team_id.keys, repos_by_id.keys)
          if PermissionCache.key?(cache_key)
            PermissionCache.get(cache_key)
          else
            GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{MOST_CAPABLE_REPO_ROLE_TEAM_CACHE_PREFIX}"])
            user_roles_assignments = UserRole.eager_load(:role).where(
              actor_type: Team, actor_id: relevant_actors_by_team_id.keys,
              target_type: Repository, target_id: repos_by_id.keys
            )

            # Get repository IDs that support the enterprise teams org roles feature
            enabled_repo_ids = repos_with_enterprise_teams_org_roles_enabled(repos_by_id)

            if enabled_repo_ids.any?
              business_team_assignments = UserRole.eager_load(:role).where(
                actor_type: BusinessTeam, actor_id: relevant_actors_by_team_id.keys,
                target_type: Repository, target_id: enabled_repo_ids
              )
              user_roles_assignments += business_team_assignments
            end

            PermissionCache.set(cache_key, user_roles_assignments)
            user_roles_assignments
          end
        end

        def fetch_most_capable_all_repo_user_role(repos_by_id, relevant_actors_by_actor_id, relevant_actors_by_team_id)
          owner_ids = repos_by_id.values.filter_map(&:owner_id).uniq

          # filter out orgs for which all repo roles isn't enabled
          all_repo_org_ids = Organization.where(id: owner_ids).pluck(:id)
          all_repo_org_business_ids = T.let(@repo_owner_business_ids.values_at(*all_repo_org_ids).compact.uniq, T::Array[Integer])

          all_repo_user_roles = []

          if all_repo_org_ids.any?
            all_repo_user_roles += Authz.domain.user_roles.base_extended_role_assignments_for(
              actor_type_to_ids: { @actor_class.name => relevant_actors_by_actor_id.keys },
              org_ids: all_repo_org_ids,
              business_ids: all_repo_org_business_ids
            )

            if relevant_actors_by_team_id.any?
              # NOTE(assyadh): check the permission cache for the all repo role team keys
              cache_key = most_capable_all_repo_role_for_team_cache_key(relevant_actors_by_team_id.keys, all_repo_org_ids)
              if PermissionCache.key?(cache_key)
                all_repo_user_roles += PermissionCache.get(cache_key)
              else
                GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{MOST_CAPABLE_ALL_REPO_ROLE_TEAM_CACHE_PREFIX}"])
                team_actor_types_and_ids = { "Team" => relevant_actors_by_team_id.keys }

                if enterprise_teams_org_roles_enabled_for_any_repo_business(repos_by_id)
                  team_actor_types_and_ids["BusinessTeam"] = relevant_actors_by_team_id.keys
                end

                all_repo_team_assignments = Authz.domain.user_roles.base_extended_role_assignments_for(
                  actor_type_to_ids: team_actor_types_and_ids,
                  org_ids: all_repo_org_ids,
                  business_ids: all_repo_org_business_ids
                )

                all_repo_user_roles += all_repo_team_assignments
                PermissionCache.set(cache_key, all_repo_team_assignments)
              end
            end
          end

          # Find most capable all repo roles for [actor.id, org.id] pairs
          most_capable_all_repo_user_roles = select_most_capable_all_repo_role(all_repo_user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id, enterprise_teams_org_roles_enabled_for_any_repo_business(repos_by_id))
          most_capable_all_repo_user_roles
        end

        # Select the most capable role per [actor, repo_id] combination
        # Returns a Hash indexed by [actor, repo] with values of the most capable user role
        def select_most_capable_roles(user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id, repos_by_id)
          roles = user_roles.map(&:role).index_by(&:id)
          enabled_repo_ids = repos_with_enterprise_teams_org_roles_enabled(repos_by_id)

          user_roles.each_with_object({}) do |user_role, result|
            # If the role is for this actor type consider all actors
            if user_role.actor_type == @actor_class.name
              relevant_actors_by_actor_id[user_role.actor_id].each do |actor|
                assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
              end
            end

            # If role is for a Team, consider all teams
            if user_role.actor_type == Team.name
              relevant_actors_by_team_id[user_role.actor_id].each do |actor|
                assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
              end
            end

            # If role is for a BusinessTeam AND the repo has the feature enabled, process it
            if user_role.actor_type == BusinessTeam.name && enabled_repo_ids.include?(user_role.target_id)
              relevant_actors_by_team_id[user_role.actor_id].each do |actor|
                assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
              end
            end
          end
        end

        # Select the most capable all repo role per [actor, org_id] combination
        # Returns a Hash indexed by [actor, org.id]
        def select_most_capable_all_repo_role(user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id, include_business_teams = false)
          # For each user role
          # If the actor type of the user role matches the request actor_type consider
          # the relevant actors.

          user_roles.each_with_object({}) do |user_role, result|
            if user_role.actor_type == @actor_class.name
              relevant_actors_by_actor_id[user_role.actor_id].each do |actor|
                assign_all_repo_user_role_if_greater(result, actor, user_role)
              end
            end

            if user_role.actor_type == Team.name || (include_business_teams && user_role.actor_type == BusinessTeam.name)
              relevant_actors_by_team_id[user_role.actor_id].each do |actor|
                assign_all_repo_user_role_if_greater(result, actor, user_role)
              end
            end
          end
        end

        # Look at a user_role and see see if the repository role is greater than the currently
        # recorded one for this actor. If it is, update the hash appropriately
        def assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
          repo = repos_by_id[user_role.target_id]
          key = [actor, repo]

          role = roles[user_role.role_id]
          recorded_user_role = result[key]

          if recorded_user_role.nil?
            result[key] = user_role
          else
            recorded_role = roles[recorded_user_role.role_id]
            is_greater = role.action_rank > recorded_role.action_rank
            is_equivalent = role.action_rank == recorded_role.action_rank
            is_direct = actor.id == user_role.actor_id && actor.class.name == user_role.actor_type
            result[key] = user_role if is_greater || (is_equivalent && is_direct)
          end
        end

        # Look at a user_role and see if the all repo role is greater than the
        # recorded one for this actor. If it is, update the hash appropriately.
        # result is an accumulator Hash indexed by [actor.id, target.type, target.id]
        # with the assigned UserRole as a value
        def assign_all_repo_user_role_if_greater(result, actor, user_role)
          key  = [actor.id, user_role.target_type, user_role.target_id]
          role = user_role.role

          recorded_user_role = result[key]
          if recorded_user_role.nil?
            result[key] = user_role
          else
            result[key] = compare_user_roles(recorded_user_role, user_role, actor)
          end
        end

        # Mapping of which actors (Team, BusinessTeam, User) will be relevant to a given team_id (Team, BusinessTeam)
        def relevant_actors_by_team_id_for(actors, repos_by_id)
          relevant_actors_by_team_id = Hash.new { |h, k| h[k] = [] }
          return relevant_actors_by_team_id unless @actor_class == User
          enabled_repo_ids = repos_with_enterprise_teams_org_roles_enabled(repos_by_id)

          if enabled_repo_ids.any?
            teams_by_actor_id = Orgs.domain.teams.team_ids_by_actor_id_for(actor_type: T.must(@actor_class.name), actor_ids: actors.map(&:id))
          else
            teams_by_actor_id = team_ids_by_actor_id_for(actors.map(&:id))
          end

          org_ids = repos_by_id.values.filter_map(&:organization_id).uniq
          team_ids = teams_by_actor_id.values.flatten.uniq

          # NOTE(assyadh): shortcut for really large orgs with lots of teams/members in the team
          cache_key = relevant_actors_by_team_id_for_cache_key(team_ids, org_ids)
          if PermissionCache.key?(cache_key)
            teams = PermissionCache.get(cache_key)
          else
            GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{RELEVANT_ACTORS_BY_TEAM_ID_CACHE_PREFIX}"])
            if enabled_repo_ids.any?
              # Use team_ids_for_orgs when enterprise_teams_org_roles is supported
              teams = Orgs.domain.teams.team_ids_for_orgs(org_ids: org_ids, team_ids: team_ids)
            else
              # Original implementation for backwards compatibility
              teams = ::Team.where(id: team_ids, organization_id: org_ids).index_by(&:id)
            end
            PermissionCache.set(cache_key, teams)
          end

          actors.each do |actor|
            team_ids = teams_by_actor_id[actor.id].flat_map do |team_id|
              teams[team_id]&.id_and_ancestor_ids || []
            end

            team_ids.uniq.each do |team_id|
              relevant_actors_by_team_id[team_id] << actor
            end
          end

          relevant_actors_by_team_id
        end

        # Mapping of which actors (Team, BusinessTeam, User) will be relevant to a given actor_id (Team, BusinessTeam, User)
        # For Users, only the user is relevant
        # For Teams, the actor and it's ancestors (parent teams) are relevant
        def relevant_actors_by_actor_id_for(actors)
          relevant_actors_by_actor_id = Hash.new { |h, k| h[k] = [] }

          actors.each do |actor|
            actor_ids = actor.is_a?(Team) ? actor.id_and_ancestor_ids : [actor.id]
            actor_ids.each do |id|
              relevant_actors_by_actor_id[id] << actor
            end
          end

          relevant_actors_by_actor_id
        end

        def team_ids_by_actor_id_for(user_ids)
          team_ids_by_actor_id = Hash.new { |h, k| h[k] = [] }
          ::Ability.distinct.where(
            actor_type: "User",
            actor_id: user_ids,
            subject_type: Team,
            priority: ::Ability.priorities[:direct],
          ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
            team_ids_by_actor_id[actor_id] << subject_id
          end

          team_ids_by_actor_id
        end

        def compare_user_roles(current, candidate, actor)
          raise Platform::Errors::Internal, "actor missing" if actor.nil?
          return current if candidate.nil?
          return candidate if current.nil?

          current_action_rank = current.role.action_rank
          raise Platform::Errors::Internal, "current user_role does not have an action_rank" if current_action_rank.nil?

          candidate_action_rank = candidate.role.action_rank
          return current if candidate_action_rank.nil?

          is_greater = candidate_action_rank > current_action_rank
          is_equivalent = candidate_action_rank == current_action_rank
          is_direct = actor.id == candidate.actor_id && actor.class.name == candidate.actor_type
          is_repo_role = candidate.target_type == "Repository"

          return candidate if is_greater || (is_equivalent && is_direct && is_repo_role)
          current
        end

        MOST_CAPABLE_ALL_REPO_ROLE_TEAM_CACHE_PREFIX = "most_capable_all_repo_role_for_team"
        def most_capable_all_repo_role_for_team_cache_key(team_ids, org_id)
          [MOST_CAPABLE_ALL_REPO_ROLE_TEAM_CACHE_PREFIX, team_ids, org_id]
        end

        MOST_CAPABLE_REPO_ROLE_TEAM_CACHE_PREFIX = "most_capable_repo_role_for_team"
        def most_capable_repo_role_for_team_cache_key(team_id, repo_ids)
          [MOST_CAPABLE_REPO_ROLE_TEAM_CACHE_PREFIX, team_id, repo_ids]
        end

        RELEVANT_ACTORS_BY_TEAM_ID_CACHE_PREFIX = "relevant_actors_by_team_id_for"
        def relevant_actors_by_team_id_for_cache_key(team_ids, org_ids)
          [RELEVANT_ACTORS_BY_TEAM_ID_CACHE_PREFIX, team_ids, org_ids]
        end
      end
    end
  end
end
