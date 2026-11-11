# typed: true
# frozen_string_literal: true

class Settings::AccountChoicesController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper
  include SettingsHelper

  before_action :login_required
  before_action :non_emu_required
  before_action :ensure_billing_enabled
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    if current_user.owned_or_billing_manager_organizations.any?
      render "account/choose"
    else
      redirect_to choose_account_link(current_user)
    end
  end
end
