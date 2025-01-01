# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Workflow < Platform::Objects::Base
      description "A workflow contains meta information about an Actions workflow file."
      model_name "Actions::Workflow"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, workflow)
        permission.async_repo_and_org_owner(workflow).then do |repo, org|
          permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, workflow)
        permission.load_repo_and_owner(workflow).then do |repo|
          repo.resources.actions.async_readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:r, :repo_id, :id]], as: "W", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |workflow|
        { prefix: :r, repo_id: workflow.repository_id, id: workflow.id }
      end

      implements Interfaces::UniformResourceLocatable

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          is_lab = params[:lab] == "true"

          repository && repository.workflows.find_from_filename(params[:workflow_file_name], is_lab: is_lab)
        end
      end

      url_fields description: "The HTTP URL for this workflow" do |workflow|
        workflow.async_repository.then do |repository|
          repository.async_owner.then do |_owner|
            workflow.permalink(include_host: false)
          end
        end
      end

      database_id_field

      created_at_field

      updated_at_field

      field :has_workflow_dispatch_trigger, Boolean, "Whether or not this workflow has a dispatch trigger on the repository's default default branch", null: false, mobile_only: true, method: :async_has_workflow_dispatch_trigger? do
        deprecated(
          start_date: Date.new(2024, 6, 23),
          reason: "`has_workflow_dispatch_trigger` is being removed because it can be misleading and only checks a repository's default branch",
          superseded_by: "Use `has_workflow_dispatch_trigger_for_branch(branch_ref)` instead.",
          owner: "stevepopovich",
        )
      end

      field :has_workflow_dispatch_trigger_for_branch, Boolean, "Whether or not this workflow has a dispatch trigger", null: false, mobile_only: true, method: :async_has_workflow_dispatch_trigger_for_branch do
        argument :branch_ref, String, "The branch to check whether this workflow has a dispatch trigger against. Not passing this argument will check the workflow's default branch", required: false
      end

      field :state, Enums::WorkflowState, "The state of the workflow.", null: false

      field :name, String, "The name of the workflow.", null: false

      field :runs, Connections.define(Objects::WorkflowRun), description: "The runs of the workflow.", null: false, connection: true do
        argument :order_by, Inputs::WorkflowRunOrder, "Ordering options for the connection",
          required: false, default_value: { field: "created_at", direction: "DESC" }
      end

      field :inputs, [WorkflowInput], "The possible inputs for dispatching this workflow", mobile_only: true, null: true, method: :dispatch_inputs do
        argument :branch_ref, String, "The branch to get inputs for. Not passing this argument will check the workflow's default branch", required: false
      end

      def runs(order_by:)
        viewer = @context[:viewer]
        workflow_runs = @object.workflow_runs
        workflow_runs = workflow_runs.where(repository_id: @object.repository_id)

        if !viewer.site_admin?
          workflow_runs = workflow_runs.where(user_hidden: false)
        end

        case order_by[:field]
        when "created_at"
          workflow_runs = workflow_runs.order(id: order_by[:direction])
        else
          workflow_runs = workflow_runs.order(order_by[:field] => order_by[:direction])
        end

        workflow_runs
      end
    end
  end
end
