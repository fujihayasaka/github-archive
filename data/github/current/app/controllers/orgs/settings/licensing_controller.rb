# typed: true
# frozen_string_literal: true

class Orgs::Settings::LicensingController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :dotcom_required

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
    if this_organization.billed_via_billing_platform?
      render "orgs/settings/licensing/index", locals: {
        view: BillingSettings::OverviewView.new(account: this_organization, current_user: current_user),
      }
    else
      render_404
    end
  end
end
