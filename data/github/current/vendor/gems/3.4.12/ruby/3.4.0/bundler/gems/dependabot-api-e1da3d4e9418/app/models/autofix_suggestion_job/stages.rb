# frozen_string_literal: true

class AutofixSuggestionJob
  module Stages
    ALL_STAGES = [
      START = :start,
      VALIDATE_DYNAMIC_WORKFLOW_RESPONSE = :validate_dynamic_workflow_response,
      SUBMIT_AUTOFIX_REQUEST = :submit_autofix_request,
      RECORD_AUTOFIX_RESPONSE = :record_autofix_response,
      CREATE_ANNOTATION = :create_annotation,
      VIEW_ANNOTATION = :view_annotation,
      APPROVE_FIX = :approve_fix,
      DISMISS_FIX = :dismiss_fix,
    ].freeze

    def self.record_success(stage:, **data)
      Dependabot::Logger.info(msg: "Autofix job stage result", **data)
      MetricsClient.increment("autofix_job.stage_result", tags: { stage: stage.to_s, result: "success" })
    end

    def self.record_error(stage:, error:, **data)
      Dependabot::Logger.error(msg: "Autofix job stage result",
                               "exception.type": error.class.name,
                               "exception.message": error.message,
                               **data)
      MetricsClient.increment("autofix_job.stage_result", tags: { stage: stage.to_s, result: "error" })
    end
  end
end
