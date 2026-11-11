# typed: true
# frozen_string_literal: true

class Hook::Event::WorkflowJobEvent < Hook::Event
  supports_targets Business, *DEFAULT_TARGETS

  description "Workflow job queued, waiting, in progress, or completed on a repository."

  event_attr :job_id, :action, required: true

  wait_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::RepositoriesActionsChecks

  def workflow_job
    record_query_counts "prehydration_workflow_job_queries" do
      @workflow_job ||= Actions::WorkflowJobRun.includes(:check_run, workflow_run: [:repository, check_suite: :creator]).find_by(id: job_id)
    end
  end

  # The repository that this event is associated with. The delivery
  # system will use this to find subscribed repository and organization
  # hooks.
  #
  # This will automatically be included in hook payloads.
  def target_repository
    @target_repository ||= workflow_job.try(:workflow_run).try(:repository)
  end

  # The user who performed the action.
  #
  # This will automatically be included in hook payloads.
  def actor
    @actor ||= workflow_job.try(:workflow_run).try(:check_suite).try(:creator) || User.ghost
  end

  def deliverable?
    workflow_job.present? && target_repository.present?
  end

  def initialize_primary_resource
    return unless super
    @workflow_job = Actions::WorkflowJobRun.new(primary_resource_data)
  end
end
