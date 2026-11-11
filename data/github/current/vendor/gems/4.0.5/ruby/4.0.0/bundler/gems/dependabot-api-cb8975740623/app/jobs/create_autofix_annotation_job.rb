# frozen_string_literal: true

class CreateAutofixAnnotationJob < ApplicationJob
  queue_as :autofix_job

  class MissingAutofixSuggestionJobError < StandardError; end

  def perform(autofix_suggestion_job_id:)
    autofix_suggestion_job = AutofixSuggestionJob.find(autofix_suggestion_job_id)
    Dependabot::Exceptions.push(autofix_suggestion_job.telemetry_attributes)

    autofix_suggestion_job.observe_stage(stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION) do
      autofix_client.create_suggested_fix_annotation(autofix_suggestion_job)
      autofix_suggestion_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::SUCCESS)
    end
  rescue ActiveRecord::RecordNotFound => e
    AutofixSuggestionJob::Stages.record_error(
      stage: AutofixSuggestionJob::Stages::CREATE_ANNOTATION,
      error: e,
      "gh.dependabot_api.autofix_suggestion_job.id": autofix_suggestion_job_id,
    )
    raise MissingAutofixSuggestionJobError
  rescue StandardError
    autofix_suggestion_job.presence&.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)
    raise
  end

  private

  def autofix_client
    Dependabot::Application.autofix_client
  end
end
