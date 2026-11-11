# typed: strict
# frozen_string_literal: true

class HydroPrPostApprovalAssessmentJob < HydroMessageJob
  queue_as :hydro_pr_post_approval_assessment

  retry_on_dirty_exit

  sig { void }
  def perform
    pull_request_id = message.dig(:pull_request, :id)

    if pull_request_id.present?
      perform_for_merge(T.cast(pull_request_id, Integer))
    else
      log("missing pull request ID")
    end
  rescue StandardError => err
    log(err.message)
    raise err
  end

  private

  sig { params(pull_request_id: Integer).void }
  def perform_for_merge(pull_request_id)
    @log_context = T.let({ "gh.pull_request.id" => pull_request_id }, T.nilable(T::Hash[String, T.untyped]))
    log("start HydroPrPostApprovalAssessmentJob (merge)")

    ActiveRecord::Base.connected_to(role: :reading) do
      pull_request = PullRequest.find_by(id: pull_request_id)
      return log("unable to find pull request #{pull_request_id}") unless pull_request.present?

      approval_reviews = all_approvals(pull_request_id: pull_request.id)
      return log("no approvals found") if approval_reviews.empty?

      approval_reviews.each do |approval_review|
        run_analyzer(pull_request:, approval_review:)
      end
    end
  end

  sig { params(pull_request: PullRequest, approval_review: PullRequestReview).void }
  def run_analyzer(pull_request:, approval_review:)
    GitHub.dogstats.increment("copilot4prs.hydro_pr_post_approval_assessment.invocations")

    analyzer = PullRequests::Copilot::CodeReview::PostApprovalAnalyzer::Analyzer.new(
      pull_request:,
      approval_review: approval_review,
      window_end_review: nil,
    )
    analyzer.analyze
  end

  sig { params(message: String).void }
  def log(message)
    context = (@log_context || {}).merge(
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
    GitHub.logger.info("hydro_pr_post_approval_assessment_job: #{message}", context)
  end

  sig { params(pull_request_id: Integer).returns(T::Array[PullRequestReview]) }
  def all_approvals(pull_request_id:)
    PullRequestReview
      .where(pull_request_id: pull_request_id)
      .where(state: PullRequestReview.state_value(:approved))
      .order(Arel.sql("COALESCE(submitted_at, created_at) ASC"))
      .to_a
  end
end
