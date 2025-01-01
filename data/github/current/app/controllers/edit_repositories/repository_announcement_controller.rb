# typed: true
# frozen_string_literal: true

class EditRepositories::RepositoryAnnouncementController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_access
  before_action :ensure_announcements_enabled

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
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

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:announcement]

  def announcement # rubocop:todo GitHub/UseRestfulActions
    current_announcement = EnterpriseBanner.active.find_by(owner: current_repository)
    render "edit_repositories/pages/announcement", locals: { banner: current_announcement }
  end

  def preview_announcement # rubocop:todo GitHub/UseRestfulActions
    render "settings/announcements/preview_announcement", locals: {
      announcement: params[:announcement_preview_value],
      user_dismissible: params[:announcement_preview_user_dismissible] == "true",
      owner: current_repository
    }
  end

  def set_announcement # rubocop:todo GitHub/UseRestfulActions
    form_payload = params[:custom_messages]
    unless form_payload
      flash[:error] = "Error setting announcement"
      return redirect_to edit_repository_announcement_path
    end

    banner = EnterpriseBanner.build_from_form(current_repository, form_payload)
    unless banner.valid?
      flash.now[:error] = "Error setting announcement: #{banner.errors.full_messages.to_sentence}"
      return render "edit_repositories/pages/announcement", locals: { banner: banner }
    end

    current_banner = EnterpriseBanner.active.find_by(owner: current_repository)
    if !current_banner.nil? && current_banner == banner
      flash[:error] = "Announcement was not saved because there were no changes."
      return redirect_to edit_repository_announcement_path
    end

    banner.upsert_for(current_repository, current_user)
    redirect_to edit_repository_announcement_path, notice: "The announcement was successfully published. It will be displayed to all users of this repository."
  end

  def destroy
    EnterpriseBanner.clear_for(current_repository, current_user)
    redirect_to edit_repository_announcement_path, notice: "Unpublished the announcement."
  end

  private

  def ensure_access
    render_404 unless current_repository.async_can_edit_announcement_banners?(current_user).sync
  end

  def ensure_announcements_enabled
    render_404 unless current_repository.supports_enterprise_banner?
  end
end
