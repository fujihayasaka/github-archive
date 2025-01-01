# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include CodeScanning::AlertsSerializer

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
    campaign = find_security_campaign(number: params[:number].to_i)
    return render_404 if campaign.nil?

    query_string = params[:query].try(:to_str)

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    allowed_repo_ids = repository_ids_from_params
    if allowed_repo_ids.nil?
      allowed_repo_ids, _ = allowed_repo_ids_and_limit_exceeded
    end

    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session:,
      organization: T.must(campaign.organization),
      security_campaign_ids: [T.must(campaign.id)],
      allowed_repository_ids: allowed_repo_ids,
      query: query_string,
    )
    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(security_campaign: campaign, query_service:, after_cursor:, before_cursor:)
    alerts = campaign_with_alerts.turboscan_alerts
    alert_links = CodeScanning::AlertLinks.load(campaign_with_alerts.repo_alert_tuples)

    payload = {
      alerts: serialized_alerts(alerts:, suggested_fixes: nil, alert_links:),
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      openWithLinksCount: campaign_with_alerts.open_with_links_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }

    render json: payload
  end
end
