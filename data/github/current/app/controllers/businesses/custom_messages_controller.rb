# typed: true
# frozen_string_literal: true

class Businesses::CustomMessagesController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :business_owner_required

  javascript_bundle :sessions

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index, :edit]

  def index
    render "businesses/custom_messages/index"
  end

  def edit
    return render_404 if message == "sign_in_message" && GitHub.auth.saml?

    case message
    when "sign_in_message"
      render "businesses/custom_messages/sign_in_message", locals: { custom_messages: custom_messages }
    when "sign_out_message"
      render "businesses/custom_messages/sign_out_message", locals: { custom_messages: custom_messages }
    when "suspended_user_message"
      render "businesses/custom_messages/suspended_user_message", locals: { custom_messages: custom_messages }
    when "authorization_provider_name"
      render "businesses/custom_messages/authorization_provider_name", locals: { custom_messages: custom_messages }
    else
      render_404
    end
  end

  def create
    create_or_update
  end

  def update
    create_or_update
  end

  private

  def message
    params[:message].to_s
  end

  memoize def custom_messages
    CustomMessages.instance
  end

  def create_or_update
    if custom_messages.create_or_update_attributes(custom_messages_params)
      redirect_to custom_messages_enterprise_path(this_business),
        notice: "Successfully updated your custom message."
    else
      render "businesses/custom_messages/index"
    end
  end

  def custom_messages_params
    params.require(:custom_messages).permit %i[
      sign_in_message
      sign_out_message
      suspended_message
      support_url
      auth_provider_name
    ]
  end

  memoize def current_sign_in_message
    custom_messages.sign_in_message
  end
  helper_method :current_sign_in_message

  memoize def current_suspended_message
    custom_messages.suspended_message
  end
  helper_method :current_suspended_message

  memoize def current_sign_out_message
    custom_messages.sign_out_message
  end
  helper_method :current_sign_out_message

  memoize def current_auth_provider_name
    custom_messages.auth_provider_name
  end
  helper_method :current_auth_provider_name
end
