# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DispatchWorkflowRun < Platform::Mutations::Base
      description "Dispatches a workflow run"
      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      argument :workflow_id, ID, "The Node ID of the workflow to run", required: true, loads: Objects::Workflow, as: :workflow
      argument :dispatch_inputs, [Inputs::WorkflowDispatchInput], "The inputs for the dispatch", required: false
      argument :branch, String, "The branch of the repository to run this workflow against", required: true

      error_fields

      def ref_qualified_name(branch)
        "refs/heads/#{branch}"
      end

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, workflow:, **inputs)
        permission.async_repo_and_org_owner(workflow).then do |workflow_repo, _org|
          permission.access_allowed?(
            :write_actions,
            resource: workflow_repo,
            current_repo: nil,
            current_org: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(workflow:, branch:, dispatch_inputs: [])
        viewer = context[:viewer]

        repository = workflow.repository
        assert_workflow_is_executable!(workflow:, repository:)

        ref_name = ref_qualified_name(branch)

        parsed_workflow = Actions::ParsedWorkflow.parse_from_yaml(repository, workflow.path, ref_name)

        if !parsed_workflow&.has_workflow_dispatch_trigger?
          raise Platform::Errors::Unprocessable.new("Workflow does not have 'workflow_dispatch' trigger")
        end

        if dispatch_inputs
          # transform the GQL input into what the ParsedWorkflow class expects
          transformed_inputs = dispatch_inputs.each_with_object({}) do |dispatch_input, hash|
            hash[dispatch_input.title_id] = dispatch_input.value
          end

          begin
            parsed_inputs = parsed_workflow.process_inputs(transformed_inputs)
          rescue ArgumentError => e
            raise Platform::Errors::ArgumentError.new(e.message)
          end

          repository.dispatch_workflow_event(
            viewer.id,
            workflow.path,
            ref_name,
            parsed_inputs
          )
        else
          repository.dispatch_workflow_event(
            viewer.id,
            workflow.path,
            ref_name,
            nil
          )
        end

        {
          success: true,
          errors: []
        }
      end

      def assert_workflow_is_executable!(workflow:, repository:)
        viewer = context[:viewer]

        unless viewer.feature_flag_enabled?(:mobile_workflow_dispatch, default: true)
          raise Platform::Errors::Unprocessable.new("not enabled")
        end

        if viewer.action_invocation_blocked?
          raise Platform::Errors::Unprocessable.new("Actions has been disabled for this user.")
        end

        if repository.action_invocation_blocked?
          raise Platform::Errors::Unprocessable.new("Actions has been disabled for this repository.")
        end

        if workflow.disabled?
          raise Platform::Errors::Unprocessable.new("Cannot trigger a 'workflow_dispatch' on a disabled workflow")
        end
      end
    end
  end
end
