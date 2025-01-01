# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProjectV2 < Platform::Mutations::Base
      description "Creates a new project."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :owner_id, ID, "The owner ID to create the project under.", required: true, loads: Unions::OrganizationOrUser
      argument :title, String, "The title of the project.", required: true

      argument :repository_id, ID, "The repository to link the project to.", required: false, loads: Objects::Repository

      argument :team_id, ID, "The team to link the project to. The team will be granted read permissions.", required: false, loads: Objects::Team

      field :project_v2, Objects::ProjectV2, "The new project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, repository: nil, team: nil, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        if user_projects_disabled_for_viewer?(permission.viewer)
          raise Errors::Unprocessable::UserProjectsDisabled.new
        end

        current_org = owner if owner.organization?

        unless owner.projects_writable_by?(permission.viewer)
          raise Errors::Forbidden.new("#{permission.viewer.display_login} does not have permission to create projects on ownerId #{owner.global_relay_id}.")
        end

        permission.async_owner_if_org(repository).then do |repo_org|
          project_v2_create_allowed = permission.access_allowed?(
            :project_v2_create,
            current_org: current_org,
            owner: owner,
            resource: owner,
            current_repo: repository,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
          repository_write_file_allowed = if repository.nil?
            true
          else
            permission.access_allowed?(
              :write_file,
              current_org: repo_org,
              resource: repository,
              current_repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end

          get_team_allowed = if team.nil?
            true
          else
            permission.access_allowed?(
              :v4_get_team,
              team: team,
              resource: current_org,
              organization: current_org,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end

          project_v2_create_allowed && repository_write_file_allowed && get_team_allowed
        end
      end

      def resolve(owner:, repository: nil, team: nil, title:)
        validate(owner, repository, team, title)
        memex = create_memex(owner, title)
        link_project_to_repository(memex, repository) unless repository.nil?
        link_project_to_team(memex, team) unless team.nil?
        { project_v2: memex }
      end

      private

      def create_memex(owner, title)
        memex = MemexProject.create_with_associations(
          owner: owner,
          creator: context[:viewer],
          title: title,
          with_mwl_enabled: true,
        )

        return memex if memex.valid? && memex.persisted?

        raise Errors::Unprocessable.new(memex.errors.full_messages.join(", "))
      end

      def link_project_to_repository(memex, repository)
        link = MemexProjectLink.new(source: repository, memex_project: memex)

        raise Errors::Unprocessable.new(link.errors.full_messages.join(", ")) unless link.save
      end

      def link_project_to_team(memex, team)
        begin
          memex.grant_role(team, "project_reader")
        rescue Permissions::Granters::RoleGranter::GrantFailure
          raise Errors::Unprocessable.new(
            "Could not link the team to the project. " \
              "Please try again later."
          )
        end
      end

      def validate(owner, repository, team, title)
        viewer = context[:viewer]
        raise Errors::Validation.new("Title cannot be empty.") if title.blank?

        if team.present?
          if owner != team.organization
            raise Errors::Validation.new("Only projects owned by the same owner as the team can be linked.")
          end

          # Following tests are for non integration users
          if viewer.user?
            raise Errors::Forbidden.new("The viewer must be a member of the team.") unless team.member?(viewer)
          elsif viewer.bot?
            installation = viewer.installation

            unless owner.projects_adminable_by?(installation) && team.visible_to?(installation)
              raise Errors::Forbidden.new(
                "The app must have write permissions on the organization projects " \
                  "and read access to organization members"
              )
            end
          end
        end

        if repository.present? && owner != repository.owner
          raise Errors::Validation.new("Only projects owned by the same owner as the repository can be linked.")
        end
      end

      private_class_method def self.user_projects_disabled_for_viewer?(viewer)
        return false unless viewer&.feature_enabled?(:memex_disabled_user_projects)

        viewer.is_enterprise_managed? &&
          viewer.businesses.none?(&:user_projects_enabled?)
      end
    end
  end
end
