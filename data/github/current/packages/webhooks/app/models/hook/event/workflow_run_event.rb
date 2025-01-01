# typed: true
# frozen_string_literal: true

class Hook::Event::WorkflowRunEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS

  description "Workflow run requested or completed on a repository."

  event_attr :run_id, :action, required: true

  # Helper method to look up the workflow_run using the id we were passed.
  def workflow_run
    record_query_counts "prehydration_workflow_run_queries" do
      @workflow_run ||= Actions::WorkflowRun.includes(:check_suite).find_by(id: run_id)
    end
  end

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    @target_repository ||= workflow_run.try(:repository)
  end

  # The workflow associated with this workflow_run
  def workflow
    workflow_run.try(:workflow)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= workflow_run.try(:check_suite).try(:creator)
  end

  def deliverable?
    workflow_run.present? && workflow.present? && workflow.active? && target_repository.present?
  end

  def initialize_primary_resource
    return unless super
    # explicit column filtering to ensure even model is resilient to migrations and database changes
    # https://github.com/github/availability/issues/2669
    valid_keys = Actions::WorkflowRun.column_names
    primary_resource_data.filter! do |key|
      valid_keys.any? { |valid_key| key.to_s == valid_key }
    end

    @workflow_run = Actions::WorkflowRun.new(primary_resource_data)
    if !FeatureFlag.vexi.enabled?(:webhooks_skip_manual_query_for_check_suite_for_workflow_run, Hook::ParentAsActor.new("repository-#{@workflow_run.repository_id}"), default: false)
      ActiveRecord::Base.connected_to_many([ApplicationRecord::RepositoriesActionsChecks], role: :writing) do
        @workflow_run.check_suite = CheckSuite.find_by(id: @workflow_run.check_suite_id, repository_id: @workflow_run.repository_id)
      end
    end
  end
end
