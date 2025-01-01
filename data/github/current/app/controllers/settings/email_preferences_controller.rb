# typed: true
# frozen_string_literal: true

class Settings::EmailPreferencesController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    GitHub.dogstats.increment("security_checkup_banner.engaged", tags: ["notice_type:#{params[:notice]}"]) if params[:notice]

    render "settings/email_preferences/show"
  end

  def show_with_email_verification_banner # rubocop:todo GitHub/UseRestfulActions
    if Organization.find_by(id: session[:inviting_organization_id])&.org_invite_email_verification_enabled?
      ActiveRecord::Base.connected_to(role: :writing) do
        current_user.reset_notice("show_link_to_org_invite")
      end
    end
    redirect_to settings_email_preferences_path
  end
end
