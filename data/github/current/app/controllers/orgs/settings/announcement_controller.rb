# typed: true
# frozen_string_literal: true

class Orgs::Settings::AnnouncementController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_announcements_supported

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:announcement],
    optional: true

  # TODO clean these up
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:announcement]

  def announcement # rubocop:todo GitHub/UseRestfulActions
    current_announcement = EnterpriseBanner.active.find_by(owner: current_organization)
    render "settings/organization/announcement", locals: { banner: current_announcement }
  end

  def preview_announcement # rubocop:todo GitHub/UseRestfulActions
    render "settings/announcements/preview_announcement", locals: {
      announcement: params[:announcement_preview_value],
      user_dismissible: params[:announcement_preview_user_dismissible] == "true",
      owner: current_organization
    }
  end

  def set_announcement # rubocop:todo GitHub/UseRestfulActions
    form_payload = params[:custom_messages]
    unless form_payload
      flash[:error] = "Error setting announcement"
      return redirect_to edit_org_announcement_path
    end

    banner = EnterpriseBanner.build_from_form(current_organization, form_payload)
    unless banner.valid?
      flash.now[:error] = "Error setting announcement: #{banner.errors.full_messages.to_sentence}"
      return render "settings/organization/announcement", locals: { banner: banner }
    end

    current_banner = EnterpriseBanner.active.find_by(owner: current_organization)
    if !current_banner.nil? && current_banner == banner
      flash[:error] = "Announcement was not saved because there were no changes."
      return redirect_to edit_org_announcement_path
    end

    banner.upsert_for(current_organization, current_user)
    redirect_to edit_org_announcement_path, notice: "The announcement was successfully published. It will be displayed to all users of this organization."
  end

  def destroy
    EnterpriseBanner.clear_for(current_organization, current_user)
    redirect_to edit_org_announcement_path, notice: "Unpublished the announcement."
  end

  private

  def ensure_current_organization
    render_404 unless current_organization
  end

  def ensure_announcements_supported
    render_404 unless current_organization.business.present?
  end
end
