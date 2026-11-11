# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ToggleProjectV2AutoAssignAgent < Platform::Mutations::Base
      docs_category :projects
      description "Enable or disable auto-assign agent for a project. When disabled, no new agent sessions are triggered by column moves."

      minimum_accepted_scopes ["project"]

      visibility :under_development

      argument :project_id, ID, "The ID of the Project to toggle auto-assign agent for.", required: true, loads: Objects::ProjectV2
      argument :enabled, Boolean, "Whether to enable or disable auto-assign agent.", required: true
      argument :workflow_number, Int, "The number of the specific auto-assign agent workflow to toggle. If omitted, all auto-assign agent workflows are toggled.", required: false

      field :project_v2, Objects::ProjectV2, "The updated Project.", null: true

      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, enabled:, workflow_number: nil, **inputs)
        unless MemexProjectFeatureCheck.enabled?(:memex_autopilot, project, actor: context[:viewer])
          raise Errors::Forbidden.new("Auto-assign agent is not available for this project")
        end

        if workflow_number
          workflow = project.workflows.find_by(trigger_type: :auto_assign_agent, number: workflow_number)
          raise Errors::Validation.new("The auto-assign agent workflow with number #{workflow_number} does not exist in the project.") if workflow.nil?
        end

        project.toggle_auto_assign_agent!(enabled: enabled, updater: context[:viewer], number: workflow_number)

        GitHub.dogstats.increment(
          "memex.auto_assign_agent_toggle.count",
          tags: [
            "enabled:#{enabled}",
            "scope:#{workflow_number.present? ? 'single_workflow' : 'bulk_workflows'}",
            "surface:graphql",
          ]
        )

        { project_v2: project }
      end
    end
  end
end
