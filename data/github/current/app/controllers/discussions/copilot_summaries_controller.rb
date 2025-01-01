# typed: true
# frozen_string_literal: true

class Discussions::CopilotSummariesController < Discussions::BaseController
  extend T::Sig

  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include CopilotChatHelper

  before_action :require_feature
  before_action :login_required
  before_action :require_copilot_enterprise
  before_action :require_discussion

  allow_verified_fetch only: [:create]
  before_action :parse_json_params, only: [:create]

  def create
    result, status = summarize_discussion_result

    unless result.is_a?(CopilotSummaryAgentResponse)
      render json: result, status: status
      return
    end

    respond_to do |format|
      format.html do
        render html: result.summary_html(viewer: current_user), status: status
      end
    end
  end

  private

  sig do
    returns([
      T.any(
        CopilotSummaryAgentResponse,
        T::Hash[Symbol, T.untyped]
      ),
      Symbol
    ])
  end
  def summarize_discussion_result
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    result = summarizer.summarize(actor: current_user, token: copilot_api_token, prompt: custom_prompt)
    [result, :ok]
  rescue CopilotAPI::NotFoundError, CopilotAPI::UnauthorizedError => err
    [{ error: err }, :not_found]
  rescue CopilotAPI::NetworkError => err
    [{ error: err }, :unprocessable_entity]
  rescue EncodingError => err
    Failbot.report(err)
    [{ error: err }, :unprocessable_entity]
  end

  sig { returns Discussion::CopilotSummarizer }
  def summarizer
    discussion = T.must_because(self.discussion) { "#require_discussion ensures non-nil" }
    Discussion::CopilotSummarizer.new(discussion: discussion)
  end

  sig { returns T.nilable(String) }
  def custom_prompt
    params[:prompt] if user_feature_enabled?(:copilot_summary_custom_prompt)
  end

  sig { returns Copilot::EncryptedToken }
  def copilot_api_token
    copilot_mint_token(user_session)
  end

  def require_feature
    super # check that discussions is enabled
    return if performed? # bail out if we've already rendered a response

    render_404 unless current_user&.copilot_discussion_summary_feature_enabled?
  end

  def require_copilot_enterprise
    current_user = T.must_because(self.current_user) { "#login_required ensures non-nil" }
    render_404 unless current_copilot_user&.has_copilot_enterprise_access?
  end
end
