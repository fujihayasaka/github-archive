# typed: true
# frozen_string_literal: true

class Discussions::CopilotSummariesController < Discussions::BaseController

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :require_feature
  before_action :login_required
  before_action :require_copilot_access
  before_action :require_discussion

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  GENERIC_ERROR_MESSAGE = "This discussion can't be summarized right now. Please try again later."
  NO_PERMISSIONS_ERROR_MESSAGE = "You don't have permission to summarize this discussion using Copilot."

  def create
    result, status = summarize_discussion_result

    respond_to do |format|
      format.json do
        render json: result, status: status
      end
    end
  end

  private

  sig { returns([Hash, Symbol]) }
  def summarize_discussion_result
    result = summarizer.summarize(prompt: custom_prompt)
    [to_success_response(result), :ok]
  rescue CopilotAPI::NotFoundError
    [to_error_response(NO_PERMISSIONS_ERROR_MESSAGE), :not_found]
  rescue CopilotAPI::UnauthorizedError # e.g., expired token
    [to_error_response(GENERIC_ERROR_MESSAGE), :unauthorized]
  rescue CopilotAPI::NetworkError
    [to_error_response(GENERIC_ERROR_MESSAGE), :unprocessable_entity]
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

  sig { returns Discussion::CopilotSummarizer }
  def summarizer
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    Discussion::CopilotSummarizer.new(discussion: discussion, actor: current_user)
  end

  sig { returns T.nilable(String) }
  def custom_prompt
    params[:prompt] if user_feature_enabled?(:copilot_summary_custom_prompt)
  end

  def require_feature
    super # check that discussions is enabled
    return if performed? # bail out if we've already rendered a response

    render_404 unless current_user&.copilot_discussion_summary_feature_enabled?
  end

  def require_copilot_access
    has_access = CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: current_user,
      copilot_user: current_copilot_user_v2)
    render_404 unless has_access
  end
end
