# typed: true
# frozen_string_literal: true

class Copilot::Chat::FeedbackController < Copilot::Chat::AbstractChatController
  allow_verified_fetch only: [:create]
  before_action :try_parse_json_params, only: [:create]

  def create
    current_user_copilot_api.send_feedback(
      feedback: params[:feedback],
      feedback_choice: Array(params[:feedback_choice]),
      thread_id: params[:thread_id],
      message_id: params[:message_id],
      text_response: params[:text_response].to_s,
      is_contacted_checked: params[:is_contacted_checked].to_s,
    )

    head :created
  rescue CopilotAPI::NotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue CopilotAPI::NetworkError => e
    report_error(e)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
