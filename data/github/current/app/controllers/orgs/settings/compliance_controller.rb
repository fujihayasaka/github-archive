# typed: true
# frozen_string_literal: true

class Orgs::Settings::ComplianceController < Orgs::Controller
  include ComplianceReportHelper

  before_action :login_required
  before_action :organization_admin_required
  before_action :ensure_compliance_reports_available

  stylesheet_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:index]

  def index
    render "settings/organization/compliance/index"
  end

  private

  def ensure_compliance_reports_available
    render_404 unless compliance_reports_available_for_account?(current_organization)
  end
end
