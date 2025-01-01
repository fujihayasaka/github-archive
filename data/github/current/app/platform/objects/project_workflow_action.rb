# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ProjectWorkflowAction < Platform::Objects::Base
      visibility :internal
      description "An action to perform as a part of an automated workflow."

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
        object.async_project_workflow.then do |project_workflow|
          permission.belongs_to_project(project_workflow)
        end
      end

      scopeless_tokens_as_minimum

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      global_id_field :id, description: "The Node ID of the ProjectWorkflowAction object", deprecated: Helpers::ProjectDeprecation::Notice # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field deprecated: Helpers::ProjectDeprecation::Notice

      created_at_field deprecated: Helpers::ProjectDeprecation::Notice
      updated_at_field deprecated: Helpers::ProjectDeprecation::Notice

      field :action_type, Enums::ProjectWorkflowActionType, "The type of action to perform for a project workflow.", null: false, deprecated: Helpers::ProjectDeprecation::Notice

      field :creator, Interfaces::Actor, "The actor who originally created the project workflow action.", method: :async_creator, null: true, deprecated: Helpers::ProjectDeprecation::Notice

      field :last_updater, Interfaces::Actor, "The actor who performed the last update to the project workflow action.", method: :async_last_updater, null: true, deprecated: Helpers::ProjectDeprecation::Notice

      field :project_workflow, Platform::Objects::ProjectWorkflow, "The project that this workflow applies to.", method: :async_project_workflow, null: false, deprecated: Helpers::ProjectDeprecation::Notice
    end
  end
end
