# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    module Authorization
      class MostCapableUserRoleOnTeam < Platform::Loader
        def self.load(user:, team:)
          user = user.ability_delegate
          team = team.ability_delegate
          team_owner_id = team.owning_organization_id

          return ::Promise.resolve(nil) unless user && team && team_owner_id
          return ::Promise.resolve(nil) unless user.ability_id && team.ability_id

          self.for.load([user.ability_id, team.ability_id, team_owner_id])
        end

        def fetch(user_and_team_and_organization_id)
          Scientist.run "most-capable-user-role-on-team" do |e|
            e.use { fetch_control(user_and_team_and_organization_id) }
            e.try { fetch_candidate(user_and_team_and_organization_id) }
          end
        end

        def fetch_control(user_and_team_and_team_owner_ids)
          user_ids, team_ids, team_owner_ids = user_and_team_and_team_owner_ids.transpose

          user_ids.uniq!
          team_ids.uniq!
          team_owner_ids.uniq!

          return [] if user_ids.empty?
          return [] if team_ids.empty?
          return [] if team_owner_ids.empty?

          team_to_owner = user_and_team_and_team_owner_ids.map { |_, team, owner| [team, owner] }.to_h

          ## Determines users with explicit direct or indirect (materialized) ability on the team
          ## This could include org admins too with action: read, indicating membership
          ##
          ## Platform::Loader.fetch returns a hash were the key is each of the elements found in the input argument.
          ## The following will be used as the result to return and is a Hash{[user_id Integer, team_id Integer, team_owner_id Integer] => Role}.
          ## The team_owner_id is not really relevant to the invoker, but is a side effect of injecting it via the load method
          loader_key_to_role = ::Ability.where(
            actor_id: user_ids,
            actor_type: "User",
            subject_id: team_ids,
            subject_type: "Team",
            priority: [::Ability.priorities[:direct], ::Ability.priorities[:indirect]]
          ).pluck(:actor_id, :subject_id, :action).map do |actor_id, subject_id, action|
            [[actor_id, subject_id, team_to_owner[subject_id]], action == "admin" ? "maintainer" : "member"]
          end.to_h

          ## Determines users with explicit direct admin ability over the team owning Organization
          # Determine from the input keys (user, team, owner) for which the user is an admin of the owner
          user_is_admin_of_org = ::Ability.
            user_admin_on_organization(actor_id: user_ids, subject_id: team_owner_ids).
            where(priority: ::Ability.priorities[:direct]).
            pluck(:actor_id, :subject_id).map do |actor_id, subject_id|
              [[actor_id, subject_id], true]
            end.to_h

          user_and_team_and_team_owner_ids
            .select { |user, _team, owner| user_is_admin_of_org[[user, owner]] == true }
            .each { |user, team, owner| loader_key_to_role[[user, team, owner]] = "maintainer" }

          loader_key_to_role
        end

        # Internal: Fetch the role the user has over the team
        #
        # Returns a Hash[Array[Integer, Integer, Integer], "member" | "maintainer"].
        def fetch_candidate(user_and_team_and_organization_id)
          user_to_team_organization_admin_mapping = build_user_to_team_organization_admin_mapping(user_and_team_and_organization_id)
          user_to_team_action_mapping = build_user_to_team_action_mapping(user_and_team_and_organization_id)

          result = Hash.new

          user_and_team_and_organization_id.each do |key|
            user_id, team_id, organization_id = *key

            if user_to_team_organization_admin_mapping.dig(user_id, organization_id)
              result[key] = "maintainer"
            elsif (action = user_to_team_action_mapping.dig(user_id, team_id))
              result[key] = if action == "admin"
                "maintainer"
              else
                "member"
              end
            end
          end

          result
        end

        # Builds a mapping between user ids and organization ids the user has admin permissions on.
        #
        # Returns a Hash[Integer, Hash[Integer, true]]
        def build_user_to_team_organization_admin_mapping(user_and_team_and_organization_id)
          result = Hash.new { |h, k| h[k] = {} }

          abilities = ::Ability.distinct.admin.where({
            actor_type: "User",
            subject_type: "Organization",
            priority: ::Ability.priorities[:direct],
          })

          values = user_and_team_and_organization_id.map { |(user_id, _, organization_id)| [user_id, organization_id] }.uniq
          conditions = ["(actor_id = ? AND subject_id = ?)"] * values.size

          abilities.where([conditions.join(" OR "), values].flatten).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
            result[actor_id][subject_id] = true
          end

          result
        end

        # Builds a mapping between user ids and the `Ability` action each user can perform
        # on a given team id.
        #
        # Returns a Hash[Integer, Hash[Integer, String]]
        def build_user_to_team_action_mapping(user_and_team_and_organization_id)
          result = Hash.new { |h, k| h[k] = {} }

          abilities = ::Ability.distinct.where(
            actor_type: "User",
            subject_type: "Team",
            priority: [::Ability.priorities[:direct], ::Ability.priorities[:indirect]]
          )

          values = user_and_team_and_organization_id.map { |(user_id, team_id, _)| [user_id, team_id] }
          conditions = ["(actor_id = ? AND subject_id = ?)"] * values.size

          abilities.where([conditions.join(" OR "), values].flatten).pluck(:actor_id, :subject_id, :action).each do |actor_id, subject_id, action|
            result[actor_id][subject_id] = action
          end

          result
        end
      end
    end
  end
end
