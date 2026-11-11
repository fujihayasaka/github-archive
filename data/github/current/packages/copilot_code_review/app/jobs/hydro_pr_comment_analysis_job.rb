# typed: strict
# frozen_string_literal: true

class HydroPrCommentAnalysisJob < HydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_pr_comment_analysis

  retry_on_dirty_exit

  sig { void }
  def perform
    @pull_id = T.let(message.dig(:pull_request, :id), T.nilable(Integer))
    return log("missing pull request ID") unless @pull_id.present?

    log("start HydroPrCommentAnalysisJob")

    ActiveRecord::Base.connected_to(role: :reading) do
      pull_request = PullRequest.find_by(id: @pull_id)
      return log("unable to find pull request #{@pull_id}") unless pull_request.present?

      GitHub.dogstats.increment("copilot4prs.hydro_pr_comment_analysis.invocations")

      analyzer = PullRequests::Copilot::CodeReview::SuggestionAcceptanceAnalyzer::Analyzer.new(pull_request:)
      analyzer.analyze

      enqueue_ccr_recall_job(pull_request)
      enqueue_competitor_recall_jobs(pull_request)
    end
  rescue StandardError => err
    log(err.message)
    raise err
  end

  private

  # Throttle CCR-subject recall analysis volume independently of competitor
  # analyses (gated by :pr_recall_analysis_competitors). The FF lives here at
  # the enqueue site — rather than inside the analyzer — so we don't pay the
  # cost of enqueuing jobs that would immediately abort.
  sig { params(pull_request: PullRequest).void }
  def enqueue_ccr_recall_job(pull_request)
    user = pull_request.user
    return if user.nil?
    return unless FeatureFlag.vexi.enabled?(:pr_recall_analysis_ccr, user, default: false)

    RecallAnalysisJob.perform_later(pull_request.id)
  end

  # Fan-out recall analysis to competitor review bots that actually reviewed
  # this PR. Pre-filters the allowlisted competitors with a single query to
  # avoid enqueuing jobs that would immediately abort in before_enqueue.
  #
  # See github/copilot-code-review#2588.
  sig { params(pull_request: PullRequest).void }
  def enqueue_competitor_recall_jobs(pull_request)
    user = pull_request.user
    return if user.nil?
    return unless FeatureFlag.vexi.enabled?(:pr_recall_analysis_competitors, user, default: false)

    competitor_ids = PullRequests::Copilot::CodeReview::RecallAnalyzer::Subjects.competitor_user_ids
    return if competitor_ids.empty?

    reviewed_subject_ids = pull_request.reviews
      .where(user_id: competitor_ids)
      .where.not(submitted_at: nil)
      .distinct
      .pluck(:user_id)

    reviewed_subject_ids.each do |subject_user_id|
      RecallAnalysisJob.perform_later(pull_request.id, subject_user_id)
    end
  end

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_pr_comment_analysis_job: #{message}",
      "gh.pull_request.id" => @pull_id,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end
end
