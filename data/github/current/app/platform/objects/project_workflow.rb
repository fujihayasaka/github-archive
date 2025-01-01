# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectWorkflow < Platform::Objects::Base
      visibility :internal
      description "Automated workflow in a project triggered by an event."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        Platform::Helpers::ProjectDeprecation.ensure_api_availability(permission.viewer)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_project(object)
      end

      scopeless_tokens_as_minimum

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the ProjectWorkflow object", deprecated: Helpers::ProjectDeprecation::Notice # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field deprecated: Helpers::ProjectDeprecation::Notice

      created_at_field deprecated: Helpers::ProjectDeprecation::Notice
      updated_at_field deprecated: Helpers::ProjectDeprecation::Notice

      field :trigger_type, Enums::ProjectWorkflowTriggerType, "The trigger type that initiates the project workflow.", null: false, deprecated: Helpers::ProjectDeprecation::Notice

      field :creator, Interfaces::Actor, "The actor who originally created the project workflow.", method: :async_creator, null: true, deprecated: Helpers::ProjectDeprecation::Notice

      field :last_updater, Interfaces::Actor, "The actor who performed the last update to the project workflow.", method: :async_last_updater, null: true, deprecated: Helpers::ProjectDeprecation::Notice

      field :project, Platform::Objects::Project, "The project that this workflow applies to.", method: :async_project, null: false, deprecated: Helpers::ProjectDeprecation::Notice
      field :project_column, Platform::Objects::ProjectColumn, "The project column that this workflow applies to.", method: :async_project_column, null: true, deprecated: Helpers::ProjectDeprecation::Notice

      url_fields visibility: :internal, description: "The HTTP edit URL for this project workflow", deprecated: Helpers::ProjectDeprecation::Notice do |workflow|
        workflow.async_project.then do |project|
          project.async_url("/project_workflows/{id}", id: workflow.global_relay_id)
        end
      end

      field :actions, Connections.define(Objects::ProjectWorkflowAction), visibility: :internal, description: "List of actions for the workflow.", null: false, connection: true, deprecated: Helpers::ProjectDeprecation::Notice

      def actions
        @object.actions.scoped
      end
    end
  end
end
