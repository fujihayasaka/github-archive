# typed: false
# frozen_string_literal: true

class Actions::WorkflowRunExecution < ApplicationRecord::Domain::RepositoriesActionsChecks
  extend GitHub::Encoding
  force_utf8_encoding :execution_graph
  force_utf8_encoding :referenced_workflows

  include ::Repositories::BelongsToRepository
  belongs_to_repository_via_domain return_type: T.nilable(Repositories::IRepository)
  belongs_to :workflow_run, -> (workflow_run_execution) { where(repository_id: workflow_run_execution.repository_id) }, inverse_of: :workflow_run_executions
  belongs_to :actor, class_name: "User"

  has_many :workflow_job_runs, -> (workflow_run_execution) { where(repository_id: workflow_run_execution.repository_id, workflow_run_id: workflow_run_execution.workflow_run_id) }, inverse_of: :workflow_run_execution

  enum :status, CheckRun.statuses
  enum :conclusion, CheckRun.conclusions.merge(startup_failure: 8)

  attribute :external_id, :uuid_type

  # execution_graph can be a large JSON blob and is only used in a few places so the default scope excludes it
  # referenced_workflows is a medium JSON blob and is only used in a few places so the default scope excludes it
  default_scope { select(column_names - %w[execution_graph referenced_workflows]) }
  scope :with_execution_graph, -> { select(column_names - ["referenced_workflows"]) }
  scope :with_referenced_workflows, -> { select(column_names - ["execution_graph"]) }

  validate :matches_workflow_run_repository

  def duration
    return (completed_at || started_at) - started_at if started_at.present?
    updated_at - created_at
  end

  def completed?
    conclusion.present?
  end

  def is_latest_execution?
    workflow_run.latest_workflow_run_execution&.id == id
  end

  def previous_execution
    workflow_run.workflow_run_executions.order(attempt: :desc).where(Actions::WorkflowRunExecution.arel_table[:attempt].lt(attempt)).first
  end

  # Calls launch to delete logs and resets this.completed_log_url
  # Used by workflow_run.delete_logs
  def delete_logs(check_suite_log_url:)
    # The check suite logs were already deleted, and are the same as the latest execution's, so we avoid deleting them again
    if completed_log_url != check_suite_log_url
      repository_global_relay_id = Repository::ActionsDependency.global_relay_id(repository_id)

      result = Launch::Twirp::artifacts_exchange_client_for_check_suite(workflow_run.check_suite).delete_build_logs(
        repository_global_id: repository_global_relay_id,
        execution_id: external_id,
      )

      if !result.call_succeeded?
        raise "Could not delete the logs from file storage"
      end
    end

    update(completed_log_url: nil)
  end

  private

  def matches_workflow_run_repository
    if workflow_run && repository_id && repository_id != workflow_run.repository_id
      errors.add(:repository, "does not match the workflow run's repository")
    end
  end
end
