# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Permissions
      class MostCapableInheritedTeamRepositoryUserRole < Platform::Loader
        def self.load(team:, repo:)
          self.for(team).load(repo.id)
        end

        def initialize(team)
          @team = team
        end

        private

        def fetch(repo_ids)
          inherited_team_ids = @team.ancestor_ids
          user_roles = UserRole.where(
            actor_id: inherited_team_ids,
            actor_type: "Team",
            target_id: repo_ids,
            target_type: "Repository",
          )

          most_capable_repo_role = select_most_capable_role(user_roles)

          owner_ids = Repository.where(id: repo_ids).pluck(:owner_id).uniq

          # filter out orgs for which all repo roles isn't enabled
          all_repo_org_ids = Organization.where(id: owner_ids).pluck(:id)
          all_repo_user_roles = []

          if all_repo_org_ids.any? && inherited_team_ids.any?
            all_repo_user_roles += find_all_repo_role_assignments(inherited_team_ids, all_repo_org_ids)
          end

          # team a <all repo read>
          #  - team b
          #  - team c <all repo read> *
          #    - team d
          # select the most capable all repo role per { team : role } combination
          most_capable_all_repo_user_roles = select_most_capable_all_repo_role(all_repo_user_roles, inherited_team_ids)

          #return most_capable_repo_role if most_capable_all_repo_user_roles.empty?

          # result hash is indexed by repo_id (target_id)
          results = repo_ids.each_with_object({}) do |repo_id, result|
            inherited_team_ids.each do |team_id|
              repo_role = most_capable_repo_role[repo_id]
              # skip if there is no repo role or if there's no inherited all repo role for this team
              next if repo_role.nil? && most_capable_all_repo_user_roles[team_id].nil?
              result[repo_id] = compare_user_roles(repo_role, most_capable_all_repo_user_roles[team_id], team_id)
            end
          end

          results
        end

        def select_most_capable_role(user_roles)
          promises = user_roles.map(&:async_role)
          results = Promise.all(promises).sync
          roles = results.index_by(&:id)

          user_roles.each_with_object({}) do |user_role, result|
            target_id = user_role.target_id
            role = roles[user_role.role_id]
            recorded_role = roles[result[target_id]&.role_id]

            if !result.key?(target_id) || role.action_rank > recorded_role.action_rank
              result[target_id] = user_role
            end
          end
        end

        # Select the most capable all repo role per team for a given list of ancestor team ids
        # Returns a Hash indexed by team
        def select_most_capable_all_repo_role(user_roles, team_ids)
          # go through each ancestor team and select the most capable all repo role
          user_roles.each_with_object({}) do |user_role, result|
            team_ids.each do |team|
              assign_all_repo_user_role_if_greater(result, team, user_role)
            end
          end
        end

        # Look at a user_role and see if the all repo role is greater than the
        # recorded one for this actor. If it is, update the hash appropriately.
        # result is an accumulator Hash indexed by team_id with the assigned UserRole as a value
        def assign_all_repo_user_role_if_greater(result, actor_id, user_role)
          org_id = user_role.target_id
          key = actor_id
          role = user_role.role

          recorded_user_role = result[key]
          if recorded_user_role.nil?
            result[key] = user_role
          else
            result[key] = compare_user_roles(recorded_user_role, user_role, actor_id)
          end
        end

        def compare_user_roles(current, candidate, actor_id)
          raise Platform::Errors::Internal, "actor missing" if actor_id.nil?
          return current if candidate.nil?
          return candidate if current.nil?

          current_action_rank = current.role.action_rank
          raise Platform::Errors::Internal, "current user_role does not have an action_rank" if current_action_rank.nil?

          candidate_action_rank = candidate.role.action_rank
          return current if candidate_action_rank.nil?

          is_greater = candidate_action_rank > current_action_rank
          is_equivalent = candidate_action_rank == current_action_rank
          is_direct = actor_id == candidate.actor_id && Team == candidate.actor_type
          is_repo_role = candidate.target.type == "Repository"

          return candidate if is_greater || (is_equivalent && is_direct && is_repo_role)
          current
        end

        # Private: Find all repo roles assigned to specific actors and orgs
        def find_all_repo_role_assignments(actor_ids, target_ids)
          UserRole.eager_load(:role).where(
            actor_type: Team, actor_id: actor_ids,
            target_type: Organization, target_id: target_ids
          ).where.not(
            role: { base_role: nil } # all repo roles has a non-nil base_role which is a system repo role
          ).where(
              # looking either for preset all repo roles or custom org roles owned by one of these orgs
              "(role.owner_type IS NULL AND role.owner_id IS NULL) OR (role.owner_type = :org_type AND role.owner_id IN (:org_ids))",
              { org_type: "Organization", org_ids: target_ids }
          )
        end
      end
    end
  end
end
