# typed: true
# frozen_string_literal: true

class Settings::AccountPreferencesController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Migrations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  USER_MIGRATION_DISPLAY_LIMIT = 5
  AGE_IN_DAYS_FOR_MIGRATIONS_TO_SHOW = 7

  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_not_enterprise_managed

  stylesheet_bundle :settings
  javascript_bundle :settings

  def show
    user_migrations = Migration.
      for_owner(current_user).
      newest.
      where("created_at > ?", AGE_IN_DAYS_FOR_MIGRATIONS_TO_SHOW.days.ago).
      limit(USER_MIGRATION_DISPLAY_LIMIT).
      includes(:file)

    if GitHub.enterprise?
      render "settings/account_preferences/show", locals: { user_migrations: user_migrations }
    else
      current_user.reload if params[:reload]
      successor_invite = current_user.get_successor_invitation

      render(
        "settings/account_preferences/show",
        locals: { user_migrations: user_migrations, successor_invite: successor_invite },
      )
    end
  end

  private

  def ensure_not_enterprise_managed
    if FeatureFlag.vexi.enabled?(:restrict_emu_account_preferences_page, current_user, default: false)
      render_404 if current_user.is_enterprise_managed?
    end
  end
end
