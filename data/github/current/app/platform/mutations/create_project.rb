# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProject < Platform::Mutations::Base
      description "Creates a new project."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :owner_id, ID, "The owner ID to create the project under.", required: true, loads: Interfaces::ProjectOwner
      argument :name, String, "The name of project.", required: true
      argument :body, String, "The description of project.", required: false
      argument :template, Enums::ProjectTemplate, "The name of the GitHub-provided template.", required: false
      argument :public, Boolean, "Whether the project is public or not.", visibility: :under_development, default_value: false, required: false
      argument :repository_ids, [ID], "A list of repository IDs to create as linked repositories for the project", required: false, loads: Objects::Repository, as: :repositories

      field :project, Objects::Project, "The new project.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        case owner
        when ::Organization
          permission.access_allowed?(:create_project,
            owner: owner,
            resource: owner,
            current_org: owner,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            organization: owner,
            current_repo: nil,
          )
        when ::Repository
          owner.async_owner.then do |repo_owner|
            org = nil
            org = repo_owner if repo_owner.is_a?(::Organization)

            permission.access_allowed?(:create_project,
              owner: owner,
              resource: owner,
              current_org: org,
              allow_integrations: true,
              allow_user_via_granular_actor: true,
              organization: org,
              current_repo: owner,
            )
          end
        when ::User
          permission.access_allowed?(:create_project,
            owner: owner,
            resource: owner,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            current_repo: nil,
          )
        else
          raise Platform::Errors::NotImplemented, "Only repository, org, and user projects are supported"
        end
      end

      def resolve(repositories: [], owner:, **inputs)
        Platform::Helpers::ProjectDeprecation.raise_if_deprecation_enabled(context[:viewer])

        inputs[:public] = false if inputs[:public].nil?
        if !owner.respond_to?(:projects)
          raise Errors::NotFound.new("Could not resolve to a node with the global id of '#{owner.global_relay_id}'")
        end

        # EMUs can't have resources with public visibility
        if inputs.key?(:public) && inputs[:public] && !Project.owner_can_have_public_projects?(owner)
          raise Errors::Forbidden.new("Public visibility is not supported for enterprise managed projects.")
        end

        context[:permission].authorize_content(:project, :create, owner: owner)

        unless owner.projects_writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to create projects on this owner.")
        end

        project = owner.projects.build
        project.name = inputs[:name]
        project.body = inputs[:body]
        project.creator = context[:viewer]
        project.public = inputs[:public] if owner.is_a?(::User) || owner.is_a?(::Organization)

        if project.public &&
             !Project.viewer_can_create_public_project?(viewer: context[:viewer], project_owner: owner)

          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to create public projects for this owner")
        end

        if project.save
          if owner.is_a?(Organization) && !context[:viewer].can_have_granular_permissions?
            # Make the user a direct admin on the project they created.
            project.update_user_permission(context[:viewer], :admin)
          end

          if inputs[:template]
            template = ProjectTemplate.load(inputs[:template])
            project.apply_template(template)
          end

          if owner.is_a?(User)
            (repositories || []).uniq.each do |repository|
              unless repository.readable_by?(context[:viewer])
                raise Errors::NotFound.new("Could not resolve to a node with the given global id.")
              end
              project.link_repository(repository, context[:viewer])
            end
          end

          { project: project }
        else
          # TODO: This error could be more specific about which attributes failed to save.
          raise Errors::Unprocessable.new(project.errors.full_messages.join(", "))
        end
      end
    end
  end
end
