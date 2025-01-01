# typed: true
# frozen_string_literal: true

class Businesses::CustomMessages::AnnouncementController < Businesses::BusinessController
  include CustomMessagesHelper

  before_action :enterprise_required
  before_action :business_owner_required

  depends_on_clusters ApplicationRecord::Mysql1, only: [:edit]

  def edit
    render "businesses/custom_messages/announcement", locals: {
      announcement: current_announcement&.text,
      expires_at: current_announcement&.expires_at,
      user_dismissible: current_announcement&.user_dismissible,
      custom_messages: CustomMessages.instance,  # PreviewableCommentFormComponent needs this :/
    }
  end

  def update
    announcement = params[:custom_messages][:announcement]
    expires_at = params[:custom_messages][:announcement_expires_at]
    if announcement&.strip.blank?
      GitHub::EnterpriseAnnouncement.clear_announcement
      notice = "Cleared the announcement."
    else
      user_dismissible = params[:custom_messages][:user_dismissible] == "true"
      result = GitHub::EnterpriseAnnouncement.set_announcement \
        announcement: announcement, expires_at: expires_at.presence, user_dismissible: user_dismissible
      if result.success?
        notice = "Successfully set the announcement."
      else
        flash[:error] = result.errors.to_sentence
        return redirect_to edit_enterprise_announcement_path(this_business)
      end
    end

    redirect_to custom_messages_enterprise_path(this_business), notice: notice
  end
end
