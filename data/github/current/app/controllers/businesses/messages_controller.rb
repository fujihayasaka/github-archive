# typed: true
# frozen_string_literal: true

class Businesses::MessagesController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:announcement]

  def announcement # rubocop:todo GitHub/UseRestfulActions
    current_announcement = EnterpriseBanner.active.find_by(owner: current_business)
    render "businesses/settings/announcement", locals: { banner: current_announcement }
  end

  def preview_announcement # rubocop:todo GitHub/UseRestfulActions
    render "settings/announcements/preview_announcement", locals: {
      announcement: params[:announcement_preview_value],
      user_dismissible: params[:announcement_preview_user_dismissible] == "true",
      owner: current_business
    }
  end

  def set_announcement # rubocop:todo GitHub/UseRestfulActions
    form_payload = params[:custom_messages]
    unless form_payload
      flash[:error] = "Error setting announcement"
      return redirect_to edit_announcement_enterprise_path
    end

    banner = EnterpriseBanner.build_from_form(current_business, form_payload)
    unless banner.valid?
      flash.now[:error] = "Error setting announcement: #{banner.errors.full_messages.to_sentence}"
      return render "businesses/settings/announcement", locals: { banner: banner }
    end

    current_banner = EnterpriseBanner.active.find_by(owner: current_business)
    if !current_banner.nil? && current_banner == banner
      flash[:error] = "Announcement was not saved because there were no changes."
      return redirect_to edit_announcement_enterprise_path
    end

    banner.upsert_for(current_business, current_user)
    redirect_to edit_announcement_enterprise_path, notice: "The announcement was successfully published. It will be displayed to all users of this enterprise."
  end

  def destroy
    EnterpriseBanner.clear_for(current_business, current_user)
    redirect_to edit_announcement_enterprise_path, notice: "Unpublished the announcement."
  end
end
