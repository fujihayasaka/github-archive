# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class WorkflowInput < Platform::Objects::Base
      description "A workflow run's possible input"
      mobile_only true

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, workflow_input)
        permission.async_repo_and_org_owner(workflow_input["workflow"]).then do |repo, org|
          permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, workflow_input)
        permission.load_repo_and_owner(workflow_input["workflow"]).then do |repo|
          repo.resources.actions.async_readable_by?(permission.viewer)
        end
      end

      field :title_id, String, "The title of this input as defined in the yaml. This acts as the unique key for this inputs", null: false
      def title_id
        @object.dig("input", 0) # The first entry is the key of the object, the name of this param defined in the YAML
      end

      field :required, Boolean, "If this input is required to not be null when dispatching this workflow",  null: false
      def required
        @object.dig("input", 1, :required)
      end

      field :description, String, "The user-facing description of this input", null: true
      def description
        @object.dig("input", 1, :description).presence
      end

      field :type, Platform::Enums::WorkflowInputType, "The type of input this is.", null: false
      def type
        type_string = @object.dig("input", 1, :type)

        if type_string == "text"
          "string"
        else
          type_string
        end
      end

      field :choices, [String], "If this is a `choice` type input, these will be the possible choices", null: true
      def choices
        @object.dig("input", 1, :options).presence
      end

      field :default_value, String, "The default value of this input", null: true
      def default_value
        @object.dig("input", 1, :default).presence
      end
    end
  end
end
