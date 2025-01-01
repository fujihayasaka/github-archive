# typed: true
# frozen_string_literal: true

class Businesses::ComplianceController < Businesses::BusinessController
  include ActionView::Helpers::TextHelper
  include BusinessesHelper
  include ComplianceReportHelper

  before_action :business_owner_required
  before_action :compliance_available
  before_action :business_not_downgraded_to_free_plan_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    user_dormancy_reports = GHECAdmin::EnterpriseDormantUsersExport.latest_for_business(business: this_business)

    render(
      "businesses/settings/compliance",
      locals: {
        user_dormancy_reports: user_dormancy_reports,
        user_dormancy_reports_url: dormant_users_exports_enterprise_path(this_business)
      }
    )
  end

  private

  def compliance_available
    # In Proxima we don't have compiance reports available, but we still need to render this page for
    # dormant user reports
    render_404 unless compliance_reports_available_for_account?(this_business) || GitHub.multi_tenant_enterprise?
  end
end
