# typed: true
# frozen_string_literal: true

class Businesses::MandatoryMessageController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :login_required
  before_action :business_owner_required

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    only: %i(edit)

  def edit
    render "businesses/custom_messages/mandatory_message", locals: {
      mandatory_message: current_mandatory_message,
      custom_messages: CustomMessages.instance,  # PreviewableCommentFormComponent needs this :/
    }
  end

  def update
    mandatory_message = params[:custom_messages][:mandatory_message]
    if mandatory_message&.strip.blank?
      MandatoryMessage.del
      notice = "Cleared the mandatory message."
    else
      clear = params[:custom_messages][:show_new_mandatory_message_to_all_users] == "true"
      MandatoryMessage.set(mandatory_message, clear_existing_viewed_records: clear)

      all_users_part = " All users will be shown the updated mandatory message." if clear
      notice = "Successfully set the mandatory message.#{all_users_part}"
    end

    redirect_to custom_messages_enterprise_path(this_business), notice: notice
  end
end
