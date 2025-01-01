# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CloneProject < Platform::Mutations::Base
      description "Creates a new project by cloning configuration from an existing project."

      # Because of the potential cross-owner scope of cloning, we require the
      # most permissive oauth scope to clone. This guarantees access to user-,
      # org-, and repo-level projects and (1) prevents us from having to compare
      # the token scope provided with two different resources and (2) does not
      # require the user to provide a token with multiple scopes. All other
      # projects enpoints accept "repo" scope so this is inline with expectations.
      minimum_accepted_scopes ["public_repo"]

      argument :target_owner_id, ID, "The owner ID to create the project under.", required: true, loads: Interfaces::ProjectOwner, as: :owner
      argument :source_id, ID, "The source project to clone.", required: true, loads: Objects::Project, as: :source_project
      argument :include_workflows, Boolean, "Whether or not to clone the source project's workflows.", required: true
      argument :name, String, "The name of the project.", required: true
      argument :body, String, "The description of the project.", required: false
      argument :public, Boolean, "The visibility of the project, defaults to false (private).", required: false

      field :project, Objects::Project, "The new cloned project.", null: true
      field :job_status_id, String, "The id of the JobStatus for populating cloned fields.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)
        # GitHub Apps are not supported for project cloning because they require
        # acccess to both the source project and target owner, which may not be
        # the same top-level owner/permissions space. To avoid confusing scenarios
        # where sometimes it works and other times it doesn't, we are blanket
        # disabling.
        case owner
        when ::Organization
          permission.access_allowed?(:create_project,
            owner: owner,
            resource: owner,
            current_org: owner,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
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
              allow_integrations: false,
              allow_user_via_granular_actor: false,
              organization: org,
              current_repo: owner,
            )
          end
        when ::User
          permission.access_allowed?(:create_project,
            owner: owner,
            resource: owner,
            current_org: nil,
            allow_integrations: false,
            allow_user_via_granular_actor: false,
            current_repo: nil,
          )
        else
          raise Platform::Errors::NotImplemented, "Only repository, org, and user projects are supported"
        end
      end

      def resolve(owner:, source_project:, **inputs)
        Platform::Helpers::ProjectDeprecation.raise_if_deprecation_enabled(context[:viewer])

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
        project.source_kind = "clone"
        project.source_id = source_project.id
        project.track_progress = source_project.track_progress

        if owner.is_a?(User)
          visibility = inputs[:public].nil? ? false : inputs[:public]
          project.public = visibility
        end

        if project.save
          if owner.is_a?(Organization) && !context[:viewer].can_have_granular_permissions?
            project.update_user_permission(context[:viewer], :admin)
          end

          project.lock!(lock_type: Project::ProjectLock::PROJECT_CLONING, actor: context[:viewer])
          status = Memex::JobStatus.create(id: PopulateClonedProjectJob.job_id)
          queued_at = Time.current

          PopulateClonedProjectJob.perform_later(project.id, source_project.id, { include_workflows: inputs[:include_workflows], queued_at: queued_at, actor_id: context[:viewer].id, status_id: status.id })

          { project: project, job_status_id: status.id }
        else
          raise Errors::Unprocessable.new(project.errors.full_messages.join(", "))
        end
      end
    end
  end
end
