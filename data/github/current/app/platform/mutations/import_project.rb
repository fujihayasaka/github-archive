# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ImportProject < Platform::Mutations::Base
      description "Creates a new project by importing columns and a list of issues/PRs."

      minimum_accepted_scopes ["public_repo", "write:org"]

      argument :owner_name, String, "The name of the Organization or User to create the Project under.", required: true
      argument :name, String, "The name of Project.", required: true
      argument :body, String, "The description of Project.", required: false
      argument :public, Boolean, "Whether the Project is public or not.", default_value: false, required: false
      argument :column_imports, [Inputs::ProjectColumnImport], "A list of columns containing issues and pull requests.", required: true

      error_fields
      field :project, Objects::Project, "The new Project!", null: true

      extras [:execution_errors]

      def self.async_api_can_modify?(permission, owner_name:, **inputs)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)

        owner = Loaders::ActiveRecord.load(::User, owner_name, column: :login, case_sensitive: false).sync

        raise Errors::Forbidden.new("Only User or Organization projects can be imported.") unless owner

        case owner
        when ::Organization
          permission.access_allowed? :create_project,
            owner: owner,
            organization: owner,
            resource: owner,
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
        when ::User
          permission.access_allowed? :create_project,
            owner: owner,
            resource: owner,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
        end
      end

      def resolve(owner_name:, **inputs)
        # Because this importer enqueues a background job that performs a
        # potentially large lookup and insert, we have added a feature flag to
        # allow us to TURN OFF the endpoint temporarily to address any
        # substantial performance issues or unforeseen abuse vectors.
        # This feature flag should ONLY BE ENABLED FOR INCIDENTS!
        if GitHub.flipper[:disable_project_importer].enabled?(@context[:viewer])
          raise Errors::ServiceUnavailable.new("Project importing is currently unavailable, please try again later.")
        end

        owner = Loaders::ActiveRecord.load(::User, owner_name, column: :login, case_sensitive: false).sync

        unless owner && !owner.hide_from_user?(@context[:viewer])
          raise Errors::NotFound, "Could not resolve to a User or Organization with the login of '#{owner_name}'."
        end

        context[:permission].authorize_content(:project, :create, owner: owner)

        unless owner.projects_enabled?
          raise Errors::Forbidden.new("Projects are not enabled for '#{owner_name}'")
        end

        unless owner.projects_writable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to create projects on '#{owner_name}'.")
        end

        project = owner.projects.build
        project.name = inputs[:name]
        project.body = inputs[:body]
        project.creator = context[:viewer]
        project.public = inputs[:public]
        project.source_kind = "imported"

        if project.save
          if owner.is_a?(Organization) && !context[:viewer].can_have_granular_permissions?
            # Make the user a direct admin on the project they created.
            project.update_user_permission(context[:viewer], :admin)
          end

          project.lock!(lock_type: Project::ProjectLock::NEW_PROJECT_IMPORT, actor: context[:viewer])

          column_imports = inputs[:column_imports].map { |column_import| column_import.to_h }
          ImportProjectJob.perform_later(context[:viewer], project, column_imports)
          GitHub.dogstats.increment("projects.import_project.success")

          { project: project, errors: [] }
        else
          GitHub.dogstats.increment("projects.import_project.failure")
          { project: nil, errors: Platform::UserErrors.mutation_errors_for_model(project) }
        end
      end
    end
  end
end
