# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include SecurityCampaigns::AlertsSerializer

  before_action :organization_read_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:index],
    optional: true

  def index
    campaign = find_security_campaign(number: params[:number])
    return render_404 if campaign.nil?

    query_string = params[:query].try(:to_str)

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(campaign, user: current_user, user_session: user_session, query_string:, after_cursor:, before_cursor:)
    alerts = campaign_with_alerts.turboscan_alerts
    alert_links = CodeScanning::AlertLinks.load(campaign_with_alerts.repo_alert_tuples)

    payload = {
      alerts: serialized_alerts(security_campaign: campaign, alerts:, suggested_fixes: {}, alert_links:),
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      openWithLinksCount: campaign_with_alerts.open_with_links_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }

    render json: payload
  end
end
