# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSpacesUserBlocksController < StafftoolsController
  before_action :dotcom_required
  before_action :copilot_spaces_stafftools_required
  before_action :require_user

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:create, :destroy]

  def create # rubocop:disable GitHub/UseRestfulActions
    reason = params[:reason].presence || "Blocked from Copilot Spaces"
    CopilotSpaces::StafftoolsHelper.block_user_from_spaces!(this_user, current_user, reason)

    redirect_to stafftools_spaces_path,
      notice: "User has been blocked from Copilot Spaces"
  rescue => e
    redirect_to stafftools_spaces_path,
      alert: "Failed to block user: #{e.message}"
  end

  def destroy # rubocop:disable GitHub/UseRestfulActions
    reason = params[:reason].presence || "Unblocked from Copilot Spaces"
    CopilotSpaces::StafftoolsHelper.unblock_user_from_spaces!(this_user, current_user, reason)

    redirect_to stafftools_spaces_path,
      notice: "User has been unblocked from Copilot Spaces"
  rescue => e
    redirect_to stafftools_spaces_path,
      alert: "Failed to unblock user: #{e.message}"
  end

  private

  def require_user
    render_404 unless this_user
  end

  def copilot_spaces_stafftools_required
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_spaces_stafftools, current_user, default: false)
  end

  def stafftools_spaces_path
    Rails.application.routes.url_helpers.stafftools_user_copilot_spaces_path(this_user)
  end
end
