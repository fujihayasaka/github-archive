# typed: true
# frozen_string_literal: true

class Settings::SecurityAnalysesController < ApplicationController
  include Settings::ControllerMethods
  include SecretScanningCustomPatternsHelper

  # Access
  before_action :login_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:show]

  depends_on_clusters \
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:show],
    optional: true

  def show
    repo_counts_by_public = current_user.repositories.group(:public).count

    render "settings/security_analyses/show", locals: {
      public_repo_count: repo_counts_by_public&.dig(true) || 0,
      repo_count: repo_counts_by_public&.values&.sum || 0,
      cursor: SecretScanningCustomPatternsHelper::get_custom_patterns_cursor(params),
      custom_patterns_query: params[:query]
    }
  end

  def update
    error_message = UpdateSecuritySettings.perform(current_user, params).try(:fetch, :error, nil)
    return redirect_to(:back, flash: { error: error_message }) if error_message.present?

    flash[:notice] = "Security settings updated for #{current_user.display_login}'s repositories."
    redirect_to settings_security_analysis_path
  end
end
