# frozen_string_literal: true

class AutofixResponseHandler
  class MissingAutofixSuggestionJobError < StandardError; end
  class SuggestedFixInvalidError < StandardError; end
  class SuggestedFixUnknownError < StandardError; end

  attr_reader :request_id, :ai_model, :ai_version, :suggested_fix, :state

  AUTOFIX_RESULT_STATE_VALID   = :DEPENDABOT_AUTOFIX_RESULT_STATE_VALID
  AUTOFIX_RESULT_STATE_ERROR   = :DEPENDABOT_AUTOFIX_RESULT_STATE_ERROR
  AUTOFIX_RESULT_STATE_INVALID = :DEPENDABOT_AUTOFIX_RESULT_STATE_INVALID
  AUTOFIX_RESULT_STATE_UNKNOWN = :DEPENDABOT_AUTOFIX_RESULT_STATE_UNKNOWN

  def self.run(message)
    request_id = message.value.fetch(:request_id)
    ai_version = message.value.fetch(:ai_version)
    ai_model = message.value.fetch(:ai_model)
    suggested_fix = ::HydroHandlers::CodeScanning::SuggestedFix.from_message(message)
    state = message.value.fetch(:state)

    new(request_id: request_id,
        ai_version: ai_version,
        ai_model: ai_model,
        suggested_fix: suggested_fix,
        state: state).run
  end

  def self.dead_letter_errors
    {
      AutofixResponseHandler::MissingAutofixSuggestionJobError => true,
      AutofixResponseHandler::SuggestedFixInvalidError => false,
      AutofixResponseHandler::SuggestedFixUnknownError => true,
    }
  end

  def initialize(request_id:, ai_model:, ai_version:, state:, suggested_fix: nil)
    @request_id = request_id
    @ai_model = ai_model
    @ai_version = ai_version
    @suggested_fix = suggested_fix
    @state = state
  end

  def run
    autofix_suggestion_job = AutofixSuggestionJob.find(request_id)
    Dependabot::Exceptions.push(autofix_suggestion_job.telemetry_attributes)

    autofix_suggestion_job.observe_stage(stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE) do
      handle_suggested_fix_state
      create_suggested_fix(autofix_suggestion_job)

      CreateAutofixAnnotationJob.perform_later(autofix_suggestion_job_id: autofix_suggestion_job.id)
    end
  rescue ActiveRecord::RecordNotFound => e
    AutofixSuggestionJob::Stages.record_error(
      stage: AutofixSuggestionJob::Stages::RECORD_AUTOFIX_RESPONSE,
      error: e,
      "gh.dependabot_api.autofix_suggestion_job.id": request_id,
    )
    raise MissingAutofixSuggestionJobError
  rescue *self.class.dead_letter_errors.keys
    # mark the check run as failed if any errors are raised that result in the message not being retried
    if autofix_suggestion_job.present?
      autofix_suggestion_job.complete_github_check_run(conclusion: GitHub::CheckRun::Conclusion::FAILURE)
    end
    raise
  end

  private

  def create_suggested_fix(autofix_suggestion_job)
    fix = SuggestedFix.create!(
      autofix_suggestion_job_id: autofix_suggestion_job.id,
      ai_version: ai_version,
      ai_model: ai_model,
      description: suggested_fix.description,
      dependency_metadata: @suggested_fix.dependency_metadata.map(&:to_h).to_json,
    )

    fix.suggested_fix_files = @suggested_fix.suggested_fix_files.map do |file|
      SuggestedFixFile.create!(
        suggested_fix_id: fix.id,
        file_path: file.file_path,
        file_path_hash: file.file_path_hash,
        file_checksum: file.file_checksum,
        diff_content: file.diff_content,
      )
    end
  rescue ActiveRecord::RecordInvalid
    raise SuggestedFixInvalidError
  end

  def handle_suggested_fix_state
    case state
    when AUTOFIX_RESULT_STATE_VALID
      nil
    when AUTOFIX_RESULT_STATE_INVALID, AUTOFIX_RESULT_STATE_ERROR
      report_autofix_response_error
    when AUTOFIX_RESULT_STATE_UNKNOWN
      report_unknown_autofix_response_error
    end
  end

  def report_autofix_response_error
    raise SuggestedFixInvalidError
  end

  def report_unknown_autofix_response_error
    raise SuggestedFixUnknownError
  end
end
