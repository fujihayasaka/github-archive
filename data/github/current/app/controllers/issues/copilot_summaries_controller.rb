# typed: true
# frozen_string_literal: true

class Issues::CopilotSummariesController < AbstractRepositoryController

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include ControllerMethods::Issues

  before_action :require_feature
  before_action :login_required
  before_action :require_copilot_access
  before_action :issue_required
  before_action :require_issues_enabled

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  GENERIC_ERROR_MESSAGE = "This issue can't be summarized right now. Please try again later."
  NO_PERMISSIONS_ERROR_MESSAGE = "You don't have permission to summarize this issue using Copilot."

  def create
    result, status = summarize_issue_result

    respond_to do |format|
      format.json do
        render json: result, status: status
      end
    end
  end

  private

  sig { returns([Hash, Symbol]) }
  def summarize_issue_result
    result = summarizer.summarize(prompt: custom_prompt)
    [to_success_response(result), :ok]
  rescue CopilotAPI::NotFoundError => err
    Failbot.report(err)
    [to_error_response(NO_PERMISSIONS_ERROR_MESSAGE), :not_found]
  rescue CopilotAPI::NetworkError
    [to_error_response(GENERIC_ERROR_MESSAGE), :unprocessable_entity]
  rescue CopilotAPI::UnauthorizedError
    [to_error_response(GENERIC_ERROR_MESSAGE), :unauthorized]
  rescue EncodingError => err
    Failbot.report(err)
    [to_error_response(GENERIC_ERROR_MESSAGE), :unprocessable_entity]
  end

  sig { params(result: CopilotSummaryAgentResponse).returns(Hash) }
  def to_success_response(result)
    {
      html: result.summary_html(viewer: current_user, repository: current_repository, cap_filter: cap_filter),
      md: result.summary,
    }
  end

  sig { params(error: String).returns(Hash) }
  def to_error_response(error)
    { error: error }
  end

  sig { returns Issue::CopilotSummarizer }
  def summarizer
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    Issue::CopilotSummarizer.new(issue: current_issue, actor: current_user)
  end

  sig { returns T.nilable(String) }
  def custom_prompt
    params[:prompt] if user_feature_enabled?(:copilot_summary_custom_prompt)
  end

  def require_feature
    render_404 unless Issue::CopilotSummarizer.feature_enabled?(viewer: current_user)
  end

  def require_issues_enabled
    unless current_issue.pull_request?
      render_404 unless current_repository.has_issues?
    end
  end

  def require_copilot_access
    has_access = CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: current_user,
      copilot_user: current_copilot_user_v2)
    render_404 unless has_access
  end
end
