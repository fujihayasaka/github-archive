# typed: true
# frozen_string_literal: true

class Businesses::CustomMessages::PreviewController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :business_owner_required

  javascript_bundle :sessions

  def create
    return render_404 if message == "sign_in_message" && GitHub.auth.saml?

    case message
    when "sign_in_message"
      @preview_message = params[:custom_message_preview_value]
      render "sessions/new", layout: "layouts/session_authentication"
    when "sign_out_message"
      @preview_message = params[:custom_message_preview_value]
      render "dashboard/logged_out", layout: "layouts/session_authentication"
    when "suspended_user_message"
      @preview_message = params[:custom_message_preview_value]
      @preview_message = default_suspended_message if @preview_message.blank?
      render "sessions/suspended", layout: "layouts/session_authentication"
    when "authorization_provider_name"
      @preview_name = params[:custom_message_preview_value]
      render "dashboard/logged_out", layout: "layouts/session_authentication"
    else
      render_404
    end
  end

  private

  def message
    params[:message].to_s
  end

  memoize def custom_messages
    CustomMessages.instance
  end
end
