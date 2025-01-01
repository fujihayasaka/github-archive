# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::ClosedSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include ReactHelper

  before_action :manage_security_products_permission_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:index],
    optional: true

  def index
    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :security_campaign_closed_campaigns,
      }
    end

    closed_campaigns_count = SecurityCampaigns::SecurityCampaign.closed.where(organization: this_organization).count

    payload = {
      closedCampaignsCounts: closed_campaigns_count,
      closedCampaignsPath: security_center_closed_security_campaigns_list_path,
      closingOrDeletingCampaignsDocsUrl: SecurityCampaigns.closing_or_deleting_docs_url(current_organization),
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Closed Security Campaigns",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      ssr: false
    )
  end
end
