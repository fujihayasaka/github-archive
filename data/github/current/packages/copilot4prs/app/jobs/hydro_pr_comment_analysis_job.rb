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
    end
  rescue StandardError => err
    log(err.message)
    raise err
  end

  private

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_pr_comment_analysis_job: #{message}",
      "gh.pull_request.id" => @pull_id,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end

end
