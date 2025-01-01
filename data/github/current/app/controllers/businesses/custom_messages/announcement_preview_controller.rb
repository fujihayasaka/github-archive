# typed: true
# frozen_string_literal: true

class Businesses::CustomMessages::AnnouncementPreviewController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :business_owner_required

  def create
    render "businesses/custom_messages/preview_announcement", locals: {
      announcement: params[:custom_message_preview_value],
      user_dismissible: params[:custom_message_preview_user_dismissible] == "true",
    }
  end
end
