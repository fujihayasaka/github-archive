# frozen_string_literal: true

class CopilotChatController < InboxController
  def chat
    message = params[:message]
    raise ArgumentError, "Message can't be blank" if message.blank?
    raise "Chat is disabled" if AdvisoryDB::Config::CurationMCP.chat_disabled?

    response = CurationMCP::Client.new(message).final_response
    html_response = helpers.markdown(response.to_s)

    render json: { message: html_response }, status: :ok
  rescue StandardError => error
    render json: { error: error.message }, status: :unprocessable_content
  end
end
