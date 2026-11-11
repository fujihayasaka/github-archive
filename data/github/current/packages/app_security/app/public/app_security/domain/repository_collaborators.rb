# typed: strict
# frozen_string_literal: true

module AppSecurity
  class Domain
    class RepositoryCollaborators < GH::Domain::Base

      # Public: Fetch the find all users that are a 'collaborator' on the given
      # repository.
      #
      # Returns a Set of Integers.
      sig do
        params(
          repo: Repository,
          viewer: User,
          action: T.nilable(Symbol),
          affiliation: T.nilable(String),
          role_name: T.nilable(Symbol)
        ).returns(T::Set[Integer])
      end
      def ids(repo, viewer, action:, affiliation:, role_name:)
        AppSecurity::Cache::RepositoryCollaboratorsClient.new(repo, viewer:, action:, affiliation:).fetch do
          get_repo_collaborator_member_ids(repo, viewer, action:, affiliation:, role_name:)
        end
      end

      private

      sig do
        params(
          repo: Repository,
          viewer: User,
          action: T.nilable(Symbol),
          affiliation: T.nilable(String),
          role_name: T.nilable(Symbol)
        ).returns(T::Set[Integer])
      end
      def get_repo_collaborator_member_ids(repo, viewer, action:, affiliation:, role_name:) # rubocop:disable Metrics/MethodLength
        # Since we're paginating the list of IDs rather than the scope itself, we
        # need to use WillPaginate::Collection#replace in order to ensure the
        # pagination link headers are correctly added to the response.
        if affiliation == "outside"
          member_ids = repo.outside_collaborators_ids(min_action: action)
        elsif affiliation == "direct"
          member_ids = repo.direct_member_ids
          if action
            member_ids &= repo.direct_or_team_member_ids(viewer:, immediate_only: false, min_action: action)
          end
        else
          member_ids = repo.direct_or_team_member_ids(
            viewer:,
            immediate_only: false,
            min_action: action
          )
        end

        if role_name
          role = T.must(Role.internal_role_by_name(role_name))

          actor_ids_by_type = ::Authz.domain.user_roles.actors_granted_role_on_target_repo(
            target_id: repo.id, role: role
          )

          user_ids  = actor_ids_by_type["User"] || []
          team_ids  = actor_ids_by_type["Team"] || []
          team_ids += actor_ids_by_type["BusinessTeam"] || []

          user_ids_by_team = Team.member_ids_of(team_ids, immediate_only: false, with_business_teams: true)

          if affiliation == "direct"
            member_ids += Set.new(user_ids) + (Set.new(user_ids_by_team) & repo.direct_member_ids)
          elsif affiliation == "outside"
            member_ids += Set.new(user_ids + user_ids_by_team) & repo.outside_collaborators_ids
          else
            member_ids += Set.new(user_ids + user_ids_by_team)
          end
        end

        member_ids
      end
    end
  end
end
