# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class WorkflowRun < Platform::Objects::Base
      description "A workflow run."
      model_name "Actions::WorkflowRun"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, workflow_run)
        workflow_run.async_check_suite.then do |check_suite|
          permission.async_repo_and_org_owner(check_suite).then do |repo, org|
            permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, workflow_run)
        workflow_run.async_check_suite.then do |check_suite|
          permission.load_repo_and_owner(check_suite).then do |repo|
            repo.resources.actions.async_readable_by?(permission.viewer)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
          # These first two templates are mistakes -- we learned later that we could have left out the repo owner.
          # But they have to stay for compatibility's sake.
          [:urwr, :user_id, :repository_id, :workflow_run_id],
          [:orwr, :organization_id, :repository_id, :workflow_run_id],
          [:wr, :repository_id, :id],
        ], as: "WFR", ready_date: "2021-05-15" do |workflow_run|
        # `created_at` is delegated to the check-suite:
        workflow_run.async_check_suite.then do
          {
            prefix: :wr,
            repository_id: workflow_run.repository_id,
            id: workflow_run.id,
          }
        end
      end

      implements Interfaces::UniformResourceLocatable

      database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this workflow run" do |workflow_run|
        workflow_run.async_repository.then do |repository|
          repository.async_owner.then do |_owner|
            workflow_run.permalink(include_host: false)
          end
        end
      end

      field :title, String, "The title of the workflow run", null: true, required_capabilities: [:mobile_only_schema_mask], method: :async_title

      field :event, String, "The event that triggered the workflow run", null: false

      # This is the same underlying values as the event field but bound to a controlled list (enum).
      # This should help client-side engineers more easily program to this field vs. a string.
      field :event_type,
        Enums::WorkflowRunEvent,
        "The event that triggered the workflow run.",
        null: false,
        required_capabilities: [:mobile_only_schema_mask],
        method: :event

      field :run_number, Int, "A number that uniquely identifies this workflow run in its parent workflow.", null: false

      field :has_multiple_attempts, Boolean, "If the workflow run has multiple attempts", null: false, required_capabilities: [:mobile_only_schema_mask]

      def has_multiple_attempts
        @object.async_latest_workflow_run_execution.then do |_|
          @object.has_multiple_attempts
        end
      end

      field :attempt_number, Int, "The attempt number of this workflow run", null: true, required_capabilities: [:mobile_only_schema_mask]

      def attempt_number
        @object.async_latest_workflow_run_execution.then do |latest_workflow_execution|
          latest_workflow_execution&.attempt
        end
      end

      field :workflow, Objects::Workflow, "The workflow executed in this workflow run.", null: false, method: :async_workflow

      field :check_suite, Objects::CheckSuite, "The check suite this workflow run belongs to.", null: false, method: :async_check_suite

      field :pending_deployment_requests, Connections.define(Objects::DeploymentRequest), description: "The pending deployment requests of all check runs in this workflow run", null: false

      def pending_deployment_requests
        viewer = @context[:viewer]

        check_run_ids = @object.async_check_suite.then do |check_suite|
          check_suite.async_github_app.then do
            check_suite.fetch_latest_waiting_check_run_ids
          end
        end

        gate_requests = check_run_ids.then do |check_run_ids|
          ::GateRequest
            .includes(gate: [{ environment: :repository }, { gate_approvers: :approver },])
            .includes(gate_approvals: [:user])
            .where(check_run_id: check_run_ids)
        end

        gate_requests.then do |gate_requests|
          grouped_requests = gate_requests.group_by { |gr| gr.gate.environment }
          deployment_requests = grouped_requests.map do |environment, gate_requests|
            gate_approvers = gate_requests.map { |gate_request| gate_request.gate.gate_approvers }.flatten
            reviewers = gate_approvers.map { |gate_approver| gate_approver.approver }
              .select { |reviewer| reviewer.is_a?(::User) || (reviewer.is_a?(::Team) && reviewer.visible_to?(viewer)) }
            reviewers_wrapper = ArrayWrapper.new(reviewers)
            can_approve = !viewer.is_a?(::User) ? false : gate_requests.any? { |gate_request| gate_request.approval_status(viewer) == "pending" }
            wait_timer = gate_requests.map { |gate_request| gate_request.gate.timeout }.max
            wait_timer_started_at = gate_requests.find { |gate_request| gate_request.gate.type == "timeout" }&.created_at
            ::DeploymentRequest.new(environment, reviewers_wrapper, can_approve, wait_timer, wait_timer_started_at)
          end
          ArrayWrapper.new(deployment_requests)
        end
      end

      field :deployment_reviews, Connections.define(Objects::DeploymentReview), description: "The log of deployment reviews", null: false

      def deployment_reviews
        @object.async_check_suite.then do |check_suite|
          ArrayWrapper.new(GateApprovalLog.where(check_suite: check_suite))
        end
      end

      field :billable_duration_in_seconds, Int, "The amount of time tracked on this workflow run in seconds. Null if unavailable.",
        null: true, required_capabilities: [:mobile_only_schema_mask]

      def billable_duration_in_seconds
        Platform::Loaders::Cache.fetch("workflow_run_billing_duration:#{@object.id}", ttl: 5.minutes) do
          # Billing methods require repository and owner to be preloaded.
          @object.async_repository.then do |repository|
            repository.async_owner.then do |_|
              if @object.has_billing_data?
                @object.billing_duration_in_seconds
              else
                nil
              end
            end
          end
        end
      end

      def self.load_from_params(params)
        Objects::Repository.load_from_params(params).then do |repository|
          repository && Actions::WorkflowRun.find_by(repository: repository, id: params[:workflow_run_id])
        end
      end

      # This essentially provides the same information that can be dotcom accessed via a URL like:
      # https://github.com/foo-org/bar-repo/actions/runs/1337/workflow
      field :file, Objects::WorkflowRunFile, description: "The workflow file", null: true

      def file
        # This could return null, see the WorkflowRunFile#wrap method for more information.
        Models::WorkflowRunFile.wrap(object)
      end
    end
  end
end
