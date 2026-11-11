# typed: strict
# frozen_string_literal: true

class HydroPrCcrDecisionAssessmentJob < HydroMessageJob
  queue_as :hydro_pr_ccr_decision_assessment

  retry_on_dirty_exit

  sig { void }
  def perform
    pull_request_id = message.dig(:pull_request, :id)

    if pull_request_id.present?
      perform_for_merge(T.cast(pull_request_id, Integer))
    else
      log("missing pull request ID")
    end
  rescue StandardError => error
    log(error.message)
    raise error
  end

  private

  sig { params(pull_request_id: Integer).void }
  def perform_for_merge(pull_request_id)
    @log_context = T.let({ "gh.pull_request.id" => pull_request_id }, T.nilable(T::Hash[String, T.untyped]))
    log("start HydroPrCcrDecisionAssessmentJob (merge)")

    pull_request = PullRequest.find_by(id: pull_request_id)
    return log("unable to find pull request #{pull_request_id}") unless pull_request.present?

    decision_runs = decision_runs_for_pull_request(pull_request)
    return log("no persisted CCR decision runs found") if decision_runs.empty?

    decision_runs.each do |decision_run|
      run_analyzer(pull_request: pull_request, decision_run: decision_run)
    end
  end

  sig do
    params(
      pull_request: PullRequest,
      decision_run: PullRequests::Copilot::CcrDecisionRunStore::DecisionRun,
    ).void
  end
  def run_analyzer(pull_request:, decision_run:)
    GitHub.dogstats.increment("copilot4prs.hydro_pr_ccr_decision_assessment.invocations")

    analyzer = PullRequests::Copilot::CodeReview::CcrDecisionAssessmentAnalyzer.new(
      pull_request: pull_request,
      decision_run: decision_run,
    )
    analyzer.analyze
  end

  sig { params(pull_request: PullRequest).returns(T::Array[PullRequests::Copilot::CcrDecisionRunStore::DecisionRun]) }
  def decision_runs_for_pull_request(pull_request)
    PullRequests::Copilot::CcrDecisionRunStore.runs_for_pull_request(pull_request_id: pull_request.id)
  end

  sig { params(message: String).void }
  def log(message)
    context = (@log_context || {}).merge(
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
    GitHub.logger.info("hydro_pr_ccr_decision_assessment_job: #{message}", context)
  end
end
