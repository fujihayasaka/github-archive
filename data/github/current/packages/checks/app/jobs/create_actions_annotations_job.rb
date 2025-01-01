# typed: true
# frozen_string_literal: true

class CreateActionsAnnotationsJob < ApplicationJob
  include GitHub::Tracing

  queue_as :checks_create_annotations

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method(
    :perform,
    span_attribute_extractor: -> (_instance, *_args, **kwargs) do
      {
        "gh.workflow_run.id" => kwargs[:workflow_run_id],
      }
    end
  )

  def perform(repo_id:, workflow_run_id:, job_id:, message:, warning_level:)
    return unless repo_id.present?
    return unless workflow_run_id.present?
    return unless job_id.present?
    return unless message.present?

    workflow_run = Actions::WorkflowRun.find_by(id: workflow_run_id)
    return unless workflow_run.present?

    check_run = CheckRun.find_by(
      repository_id: repo_id,
      id: workflow_run.latest_workflow_run_execution.workflow_job_runs.select(:check_run_id),
      external_id: job_id
    )

    return unless check_run.present?

    with_write do
      CheckAnnotation.create!(
        filename: CheckAnnotation::ACTIONS_SYSTEM_PATH,
        repository_id: repo_id,
        check_run: check_run,
        warning_level: warning_level || "warning",
        message: message,
        start_line: 1,
        end_line: 1,
      )
    end
  end
end
