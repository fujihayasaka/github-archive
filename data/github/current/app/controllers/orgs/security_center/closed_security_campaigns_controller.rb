# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::ClosedSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController

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
    open_campaigns_count = SecurityCampaigns::SecurityCampaign.open.where(organization: this_organization).count

    payload = {
      organizationLogin: this_organization.display_login,
      closedCampaignsCounts: closed_campaigns_count,
      closedCampaignsPath: security_center_closed_security_campaigns_list_path,
      closingOrDeletingCampaignsDocsUrl: SecurityCampaigns.closing_or_deleting_docs_url,
      campaignsGAEnabled:  SecurityCampaigns.campaigns_ga_enabled?(current_user),
      openCampaignsCounts: open_campaigns_count,
      maxOpenCampaigns: SecurityCampaigns::MAX_OPEN_CAMPAIGNS_COUNT
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Security · Closed Security Campaigns",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      disable_ssr: true
    )
  end
end
