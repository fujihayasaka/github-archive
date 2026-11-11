# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # Job to trigger CodeQL analysis for a single repository in a Code Security Risk Assessment.
  #
  # Enqueued from CodeScanningAssessment.create_assessment_for_org — one job per
  # code_scanning_assessment_repository row. Loads the repository record, computes
  # supported languages, and calls the Turboscan TWIRP endpoint to trigger a dynamic
  # Actions workflow for the analysis.
  #
  # Retries are handled by ActiveJob's retry_on mechanism with polynomial backoff.
  # After exhausting TWIRP_MAX_ATTEMPTS, the repository is transitioned to failed.
  class TriggerCodeScanningAssessmentJob < ApplicationJob
    class TwirpTriggerError < StandardError; end

    TWIRP_MAX_ATTEMPTS = 3

    queue_as :code_scanning_assessment

    use_primaries ApplicationRecord::SecurityProductsEnablement

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    retry_on TwirpTriggerError, wait: :polynomially_longer, attempts: TWIRP_MAX_ATTEMPTS do |job, error|
      job.send(:on_twirp_retries_exhausted, error)
    end

    sig { params(code_scanning_assessment_repository_id: Integer).void }
    def perform(code_scanning_assessment_repository_id:)
      @assessment_repo = T.let(
        CodeScanningAssessmentRepository.find_by(id: code_scanning_assessment_repository_id),
        T.nilable(CodeScanningAssessmentRepository),
      )

      unless @assessment_repo
        log_error("Assessment repository not found", assessment_repo_id: code_scanning_assessment_repository_id)
        return
      end

      unless @assessment_repo.requested?
        log_info("Skipping non-requested repository",
          assessment_repo_id: @assessment_repo.id,
          status: @assessment_repo.status,
        )
        return
      end

      repository = T.cast(@assessment_repo.repository, T.nilable(::Repository))

      unless repository
        transition_to_failed(@assessment_repo, "Repository not found")
        return
      end

      languages = compute_supported_languages(repository)

      if languages.nil?
        transition_to_failed(@assessment_repo, "Failed to compute supported languages")
        return
      end

      if languages.empty?
        transition_to_failed(@assessment_repo, "No supported CodeQL languages detected")
        return
      end

      assessment = T.must(@assessment_repo.assessment)

      twirp_options = build_twirp_options(
        assessment: assessment,
        repository: repository,
        languages: languages,
      )

      resp = trigger_risk_assessment(twirp_options)

      # Atomic conditional update to prevent duplicate transitions if the job is
      # delivered more than once. update_all skips ActiveRecord callbacks/validations,
      # which is acceptable — this model has no callbacks for this transition.
      rows = CodeScanningAssessmentRepository
        .where(id: @assessment_repo.id, status: :requested)
        .update_all(status: :pending, workflow_id: resp.data.workflow_run_id.to_s)

      return unless rows > 0

      log_info("Successfully triggered scan",
        assessment_id: assessment.id,
        repository_id: repository.id,
        workflow_run_id: resp.data.workflow_run_id,
      )
    end

    private

    # Calls the Turboscan TWIRP endpoint. Raises TwirpTriggerError on failure
    # so that ActiveJob retry_on can handle retries with backoff.
    sig { params(twirp_options: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
    def trigger_risk_assessment(twirp_options)
      resp = begin
        GitHub::Turboscan::RiskAssessment.trigger_risk_assessment(twirp_options)
      rescue => e
        raise TwirpTriggerError, e.message
      end

      if resp&.data && !resp.error
        # Protobuf int64 fields default to 0 when unset, so a zero workflow_run_id
        # means Turboscan did not actually create the Actions workflow.
        if resp.data.workflow_run_id == 0
          raise TwirpTriggerError, "response missing workflow_run_id"
        end

        resp
      else
        raise TwirpTriggerError, resp&.error&.msg || "nil response"
      end
    end

    sig { params(error: StandardError).void }
    def on_twirp_retries_exhausted(error)
      return unless @assessment_repo

      transition_to_failed(@assessment_repo, error.message)
    end

    sig do
      params(
        assessment: CodeScanningAssessment,
        repository: ::Repository,
        languages: T::Array[String],
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def build_twirp_options(assessment:, repository:, languages:)
      {
        owner_id: assessment.owner_id,
        repository_id: repository.id,
        assessment_id: assessment.id,
        languages: languages,
        global_repository_id: global_repository_id_for(repository),
        ref: "refs/heads/#{repository.default_branch}",
      }
    end

    sig { params(repository: ::Repository).returns(T.nilable(T::Array[String])) }
    def compute_supported_languages(repository)
      ::CodeScanning::ManagedAnalysesLanguageSupport
        .new(repository, :CODE_SCANNING)
        .supported_languages
    rescue => e
      log_error("Failed to compute supported languages",
        repository_id: repository.id,
        error: e.message,
      )
      nil
    end

    sig { params(repository: ::Repository).returns(String) }
    def global_repository_id_for(repository)
      GitHub.enterprise? ? repository.global_relay_id : repository.next_global_id
    end

    sig { params(assessment_repo: CodeScanningAssessmentRepository, reason: String).void }
    def transition_to_failed(assessment_repo, reason)
      # Error messages are typically short, but truncation is a safeguard in case of unforeseen issues.
      rows = CodeScanningAssessmentRepository
        .where(id: assessment_repo.id, status: :requested)
        .update_all(status: :failed, failure_reason: reason.truncate(255))

      return unless rows > 0

      log_error("Repository scan failed",
        assessment_repo_id: assessment_repo.id,
        repository_id: assessment_repo.repository_id,
        reason: reason,
      )

      assessment_repo.assessment&.refresh_status!
    end

    sig { params(message: String, context: T.untyped).void }
    def log_info(message, **context)
      GitHub.logger.info(message, log_context(**context))
    end

    sig { params(message: String, context: T.untyped).void }
    def log_error(message, **context)
      GitHub.logger.error(message, log_context(**context))
    end

    sig { params(context: T.untyped).returns(T::Hash[String, T.untyped]) }
    def log_context(**context)
      {
        "code.namespace" => self.class.name,
      }.merge(context.transform_keys { |k| "gh.csra.#{k}" })
    end
  end
end
