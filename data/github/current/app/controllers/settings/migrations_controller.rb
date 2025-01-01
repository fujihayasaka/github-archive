# typed: false
# frozen_string_literal: true

class Settings::MigrationsController < ApplicationController
  include Settings::ControllerMethods
  include BusinessesHelper
  include OrganizationsHelper
  include SettingsHelper
  include TwoFactorHelper

  stylesheet_bundle :settings
  javascript_bundle :settings
  javascript_bundle :sessions

  before_action :sudo_filter, only: [:start, :download, :delete]
  before_action :download_everything_button_feature_required
  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:email],
    key: :migration_email_rate_limit_key,
    max: 5,
    ttl: 1.hour,
    at_limit: :email_rate_limit_render

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Migrations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:download]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:download],
    optional: true

  def start # rubocop:todo GitHub/UseRestfulActions
    return render_404 if current_user.is_enterprise_managed?

    begin
      warnings = GitHub.migrator.download_everything(current_user)

      if warnings.any?
        flash[:notice] = warnings.join(" ")
      else
        flash[:notice] = "Export started."
      end

      if current_user.feature_enabled?(:windbeam_exports) && !current_user.bot?
        WindbeamExportJob.perform_later(current_user.id)
      end
    rescue GitHub::MigrationCoordinator::RateLimitExceeded
      flash[:error] = "You've reached the maximum number of exports at this time. Please try again later."
    ensure
      redirect_to settings_account_preferences_path
    end
  end

  def email # rubocop:todo GitHub/UseRestfulActions
    migration = Migration.find_by_id(params[:migration_id])
    return render_404 unless migration && migration.owner == current_user

    migration.send_user_migration_email

    flash[:notice] = "An email has been sent to you with a link to your export."
    redirect_to settings_account_preferences_path
  end

  def download # rubocop:todo GitHub/UseRestfulActions
    url = Migration.token_to_url(params[:token], current_user)
    return render_404 unless url

    # We have to do a meta redirect to avoid CSP issues.
    # See https://github.com/github/communities/issues/771.
    render "settings/migrations/download",
      locals: { redirect_url: url },
      layout: "layouts/redirect"
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    migration = Migration.find_by_id(params[:migration_id])
    return render_404 unless migration && current_user == migration.owner

    MigrationDestroyFileJob.enqueue(migration)
    GitHub.dogstats.increment("download_everything.delete")
    flash[:notice] = "Job queued to delete file."
    redirect_to settings_account_preferences_path
  end

  private

  def migration_email_rate_limit_key
    "migration-email:#{current_user.id}"
  end

  def download_everything_button_feature_required
    render_404 unless GitHub.download_everything_button_enabled?
  end

  def email_rate_limit_render
    message = "You have exceeded our migration email rate limit. You will not be able to request another migration email for the next hour."
    render status: 422, plain: message
  end
end
