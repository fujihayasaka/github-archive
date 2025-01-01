# typed: strict
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2Collaborators < Platform::Mutations::Base
      extend T::Sig

      description "Update the collaborators on a team or a project"

      minimum_accepted_scopes ["project", "read:org"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the project to update the collaborators for.", required: true, loads: Objects::ProjectV2

      argument :collaborators, [Inputs::ProjectV2Collaborator], "The collaborators to update.", required: true

      field :collaborators,
        Connections.define(Unions::ProjectV2Actor),
        "The collaborators granted a role",
        connection: true,
        numeric_pagination_enabled: true,
        null: true

      sig do
        params(
          permission: Platform::Authorization::Permission,
          project: MemexProject,
          collaborators: T::Array[Platform::Inputs::ProjectV2Collaborator::Collaborator]
        ).returns(
          Promise[Promise[T::Boolean]]
        )
      end
      def self.async_api_can_modify?(permission, project:, collaborators:)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        if collaborators.empty?
          raise Errors::ArgumentError.new("One or more collaborators must be provided")
        end

        users, teams = collaborators
          .map do |collaborator|
            if (collaborator.team || collaborator.user).nil?
              raise Errors::ArgumentError.new("One user/team ID must be provided for each collaborator")
            end

            if (collaborator.team && collaborator.user).present?
              raise Errors::ArgumentError.new("Only one user/team ID can be provided for each collaborator")
            end
            collaborator
          end
          .group_by { |c| (c.team || c.user).class.to_s }
          .values_at("User", "Team")

        project.async_owner.then do |owner|
          raise Errors::ArgumentError.new("Project owner not found") unless owner.present?

          if owner.user? && teams&.present?
            raise Errors::ArgumentError.new("Team collaborators can only be provided for organization owned projects")
          end

          checks = if teams.present?
            teams.map do |collaborator|
              T.must(collaborator.team).async_organization.then do |team_organization|
                unless owner == team_organization
                  raise Errors::Unprocessable.new("Team and project must belong to the same organization")
                end
                Helpers::ProjectV2.async_api_can_modify_team_project_link?(
                  permission,
                  project: project,
                  team: collaborator.team
                )
              end
            end
          else
            []
          end

          if users.present?
            checks.concat(
              users.map do
                current_org = owner if owner.organization?
                permission.access_allowed?(
                  :project_v2_admin,
                  current_org: current_org,
                  resource: project,
                  current_repo: nil,
                  allow_integrations: true,
                  allow_user_via_granular_actor: true
                )
              end
            )
          end
          Promise.all(checks).then { |checks| checks.all? }
        end
      end

      sig do
        params(
          project: MemexProject,
          collaborators: T::Array[Inputs::ProjectV2Collaborator::Collaborator]
        ).returns(Promise[{ collaborators: ArrayWrapper }])
      end
      def resolve(project:, collaborators:)
        Promise.all(
          collaborators
            .map do |collaborator|
              actor_type = if collaborator.team
                Loaders::MemexProjectUserRoleByActorAndProject::ActorType::Team
              else
                Loaders::MemexProjectUserRoleByActorAndProject::ActorType::User
              end
              update_role(
                T.must(collaborator.team || collaborator.user),
                collaborator.role,
                project,
                actor_type
              ).then { |actor| actor }
            end
          ).then { |actors| { collaborators: ArrayWrapper.new(actors.compact) } }
      end

      private

      sig do
        params(
          actor: T.any(Team, User),
          role: T.nilable(String),
          project: MemexProject,
          actor_type: T.any(
            Loaders::MemexProjectUserRoleByActorAndProject::ActorType::Team,
            Loaders::MemexProjectUserRoleByActorAndProject::ActorType::User
          )
        ).returns(
          Promise[T.nilable(T.any(Team, User))]
        )
      end
      def update_role(actor, role, project, actor_type)
        internal_role = role.present? ? Role.internal_role_by_name(role) : nil

        Loaders::MemexProjectUserRoleByActorAndProject.load(
          project_id: project.id,
          actor_id: actor.id,
          actor_type: actor_type
        ).then do |roles|
          if roles.empty?
            next if internal_role.nil?

            begin
              result = project.grant_role(actor, internal_role)
            rescue Permissions::Granters::RoleGranter::GrantFailure => e
              GitHub.logger.error({
                exception: e,
                "gh.memex.project.id": project.id,
                "gh.request_id": GitHub.context[:request_id]
              })
              raise Errors::Unprocessable.new("Could not grant role to node #{actor.global_relay_id}. Please try again later.")
            end
          elsif internal_role.present?
            T.must(roles.first).update!(role: internal_role)
          else
            T.must(roles.first).destroy!
          end

          next actor
        end
      end
    end
  end
end
