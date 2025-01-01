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
        end

        # entries is an Array of [actor (User, Team), Repository] that we're trying to look up
        # return is a Hash indexed by the entries with the most capable user_role as the value
        def fetch(entries)
          actors, repos = entries.transpose
          repos_by_id = repos.index_by(&:id)

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

          # For each [actor, repo] pair in results_by_entry compare against [actor, repo.owner] and select the all repo role if more capable
          entries.each do |key|
            actor, repo = key
            org_id = repo.owner_id
            next if org_id.nil?
            most_capable_repo_user_role = results_by_entry[key]
            most_capable_all_repo_user_role = most_capable_all_repo_user_roles[[actor.id, org_id]]
            next if most_capable_all_repo_user_role.nil?
            results_by_entry[key] = compare_user_roles(most_capable_repo_user_role, most_capable_all_repo_user_role, actor)
          end
          results_by_entry
        end

        private

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
            PermissionCache.set(cache_key, user_roles_assignments)
            user_roles_assignments
          end
        end

        def fetch_most_capable_all_repo_user_role(repos_by_id, relevant_actors_by_actor_id, relevant_actors_by_team_id)
          owner_ids = repos_by_id.values.filter_map(&:owner_id).uniq

          # filter out orgs for which all repo roles isn't enabled
          all_repo_org_ids = Organization.where(id: owner_ids).pluck(:id)
          all_repo_user_roles = []

          if all_repo_org_ids.any?
            all_repo_user_roles += find_all_repo_role_assignments(@actor_class, relevant_actors_by_actor_id.keys, all_repo_org_ids)

            if relevant_actors_by_team_id.any?
              # NOTE(assyadh): check the permission cache for the all repo role team keys
              cache_key = most_capable_all_repo_role_for_team_cache_key(relevant_actors_by_team_id.keys, all_repo_org_ids)
              if PermissionCache.key?(cache_key)
                all_repo_user_roles += PermissionCache.get(cache_key)
              else
                GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{MOST_CAPABLE_ALL_REPO_ROLE_TEAM_CACHE_PREFIX}"])
                all_repo_team_assignments = find_all_repo_role_assignments(Team, relevant_actors_by_team_id.keys, all_repo_org_ids)
                all_repo_user_roles += all_repo_team_assignments
                PermissionCache.set(cache_key, all_repo_team_assignments)
              end
            end
          end

          # Find most capable all repo roles for [actor.id, org.id] pairs
          most_capable_all_repo_user_roles = select_most_capable_all_repo_role(all_repo_user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id)
          most_capable_all_repo_user_roles
        end

        # Select the most capable role per [actor, repo_id] combination
        # Returns a Hash indexed by [actor, repo] with values of the most capable user role
        def select_most_capable_roles(user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id, repos_by_id)
          roles = user_roles.map(&:role).index_by(&:id)

          user_roles.each_with_object({}) do |user_role, result|
            # If the role is for this actor type consider all actors
            if user_role.actor_type == @actor_class.name
              relevant_actors_by_actor_id[user_role.actor_id].each do |actor|
                assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
              end
            end

            # If the role is for a team also consider all teams
            if user_role.actor_type == Team.name
              relevant_actors_by_team_id[user_role.actor_id].each do |actor|
                assign_user_role_if_greater(result, roles, actor, user_role, repos_by_id)
              end
            end
          end
        end

        # Select the most capable all repo role per [actor, org_id] combination
        # Returns a Hash indexed by [actor, org.id]
        def select_most_capable_all_repo_role(user_roles, relevant_actors_by_actor_id, relevant_actors_by_team_id)
          # For each user role
          # If the actor type of the user role matches the request actor_type consider
          # the relevant actors.
          user_roles.each_with_object({}) do |user_role, result|
            if user_role.actor_type == @actor_class.name
              relevant_actors_by_actor_id[user_role.actor_id].each do |actor|
                assign_all_repo_user_role_if_greater(result, actor, user_role)
              end
            end

            # If the role is for a team also consider ancestor teams
            if user_role.actor_type == Team.name
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
        # result is an accumulator Hash indexed by [actor.id, org.id] with the assigned UserRole as a value
        def assign_all_repo_user_role_if_greater(result, actor, user_role)
          org_id = user_role.target_id
          key = [actor.id, org_id]
          role = user_role.role

          recorded_user_role = result[key]
          if recorded_user_role.nil?
            result[key] = user_role
          else
            result[key] = compare_user_roles(recorded_user_role, user_role, actor)
          end
        end

        # Mapping of which actors (Team, User) will be relevant to a given team_id (Team)
        def relevant_actors_by_team_id_for(actors, repos_by_id)
          relevant_actors_by_team_id = Hash.new { |h, k| h[k] = [] }
          return relevant_actors_by_team_id unless @actor_class == User

          teams_by_actor_id = team_ids_by_actor_id_for(actors.map(&:id))

          org_ids = repos_by_id.values.filter_map(&:organization_id).uniq
          team_ids = teams_by_actor_id.values.flatten.uniq

          # NOTE(assyadh): shortcut for really large orgs with lots of teams/members in the team
          cache_key = relevant_actors_by_team_id_for_cache_key(team_ids, org_ids)
          if PermissionCache.key?(cache_key)
            teams = PermissionCache.get(cache_key)
          else
            GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{RELEVANT_ACTORS_BY_TEAM_ID_CACHE_PREFIX}"])
            teams = ::Team.where(id: team_ids, organization_id: org_ids).index_by(&:id)
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

        # Mapping of which actors (Team, User) will be relevant to a given actor_id (Team, User)
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
            subject_type: "Team",
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
          is_repo_role = candidate.target.type == "Repository"

          return candidate if is_greater || (is_equivalent && is_direct && is_repo_role)
          current
        end

        # Private: Find all repo roles assigned to specific actors and orgs
        def find_all_repo_role_assignments(actor_type, actor_ids, target_ids)
          UserRole.eager_load(:role).where(
            actor_type: actor_type, actor_id: actor_ids,
            target_type: Organization, target_id: target_ids
          ).where.not(
            role: { base_role: nil } # all repo roles has a non-nil base_role which is a system repo role
          ).where(
              # looking either for preset all repo roles or custom org roles owned by one of these orgs
              "(role.owner_type IS NULL AND role.owner_id IS NULL) OR (role.owner_type = :org_type AND role.owner_id IN (:org_ids))",
              { org_type: "Organization", org_ids: target_ids }
          )
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
