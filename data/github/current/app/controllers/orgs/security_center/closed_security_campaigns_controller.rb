# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::ClosedSecurityCampaignsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  extend T::Sig

  include ReactHelper

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
    # User will always be available because of :login_required in AbstractSecurityCampaignsController
    return render_404 unless T.must(current_user).feature_enabled?(:security_campaigns_closed)

    data = log_timing(step: "build layout data") do
      {
        backfill_in_progress: this_organization.trigger_security_center_reconciliation,
        selected_tab: :security_campaign_closed_campaigns,
      }
    end

    closed_campaigns_count = SecurityCampaigns::SecurityCampaign.closed.where(organization: this_organization).count

    payload = {
      closedCampaignsCounts: closed_campaigns_count
    }

    render_react_app(
      app_name: "security-campaigns",
      payload:,
      title: "Closed Security Campaign",
      layout: "layouts/security_center/with_sidebar",
      page_data: { data: },
      ssr: false
    )
  end
end
