# typed: true
# frozen_string_literal: true

class Orgs::Settings::LicensingController < Orgs::Controller
  include Billing::Platform::Api::Utils

  before_action :login_required
  before_action :ensure_current_organization
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required
  before_action :org_billed_via_billing_platform
  before_action :org_admin_or_billing_manager_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    render "orgs/settings/licensing/index", locals: {
      view: BillingSettings::OverviewView.new(account: this_organization, current_user: current_user),
    }
  end

  private

  def org_billed_via_billing_platform
    render_404 unless this_organization.billed_via_billing_platform?
  end

  def org_admin_or_billing_manager_required
    render_404 unless org_admin_or_billing_manager?(entity: this_organization, current_user: current_user)
  end
end
