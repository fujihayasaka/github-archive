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

      global_id_field :id, description: "The Node ID of the ProjectWorkflowAction object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      database_id_field

      created_at_field
      updated_at_field

      field :action_type, Enums::ProjectWorkflowActionType, "The type of action to perform for a project workflow.", null: false

      field :creator, Interfaces::Actor, "The actor who originally created the project workflow action.", method: :async_creator, null: true

      field :last_updater, Interfaces::Actor, "The actor who performed the last update to the project workflow action.", method: :async_last_updater, null: true

      field :project_workflow, Platform::Objects::ProjectWorkflow, "The project that this workflow applies to.", method: :async_project_workflow, null: false
    end
  end
end
