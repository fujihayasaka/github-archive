# typed: true
# frozen_string_literal: true

class Settings::RepositoriesController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "settings/repositories/index"
  end

  def update
    updated = case params[:policy]
    when "enabled_by_default"
      current_user.enable_commit_comments_by_default(actor: current_user)
    when "disabled_by_default"
      current_user.disable_commit_comments_by_default(actor: current_user)
    end

    flash[:notice] = "Commit comments settings were updated." if updated

    redirect_to settings_repositories_path
  end
end
