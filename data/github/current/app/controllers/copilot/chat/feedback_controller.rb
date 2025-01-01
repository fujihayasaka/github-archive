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

  def interview_survey # rubocop:disable GitHub/UseRestfulActions
    return render_404 unless feature_enabled_globally_or_for_user?(feature_name: :copilot_chat_interview_survey)
    redirect_to "https://survey3.medallia.com/?55Gk0g-U1pmxhUrv3KayVT&UID=#{current_user.display_login}"
  end

  private

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  depends_on_clusters \
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:interview_survey]
end
