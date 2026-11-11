# typed: true
# frozen_string_literal: true

class Orgs::CommitCommentsSettingsController < Orgs::Controller
  before_action :org_admins_only
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def update
    updated = case params[:policy]
    when "enabled_by_default"
      current_organization.enable_commit_comments_by_default(actor: current_user)
    when "disabled_by_default"
      current_organization.disable_commit_comments_by_default(actor: current_user)
    end

    flash[:notice] = "Commit comments settings were updated." if updated

    redirect_to settings_org_repo_defaults_path(current_organization)
  end
end
