# typed: true
# frozen_string_literal: true

class Settings::OrganizationsController < ApplicationController
  include Settings::ControllerMethods
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :can_view_organizations_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    view = create_view_model(Settings::OrgsView)

    render "settings/organizations/index", locals: { view: view }
  end

  private

  def can_view_organizations_required
    render_404 if current_user&.is_enterprise_managed? && current_user&.enterprise_managed_business&.seats_plan_basic?
  end
end
