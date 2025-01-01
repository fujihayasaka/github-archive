# typed: strict
# frozen_string_literal: true

class Settings::EnterprisesController < ApplicationController
  include Settings::ControllerMethods
  include Settings::EnterprisesControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    render "settings/enterprises/index", locals: {
      businesses: businesses(user: current_user),
      show_trial_information: show_trial_information?(user: current_user),
      invitations: invitations(user: current_user),
      show_upsells: show_upsells?(user: current_user),
    }
  end
end
