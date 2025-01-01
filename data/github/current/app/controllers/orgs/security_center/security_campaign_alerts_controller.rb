# typed: true
# frozen_string_literal: true

class Orgs::SecurityCenter::SecurityCampaignAlertsController < Orgs::SecurityCenter::AbstractSecurityCampaignsController
  include CodeScanning::AlertsSerializer
  include SecurityCampaigns::AlertResultsHelper

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

    payload = if campaign.alert_type == "secret_scanning"
      get_secret_scanning_alerts(campaign, query_string, after_cursor, before_cursor)
    else
      get_code_scanning_alerts(campaign, query_string, after_cursor, before_cursor)
    end

    render json: payload
  end

  private

  sig do
    params(
      campaign: SecurityCampaigns::SecurityCampaign,
      query_string: T.nilable(String),
      after_cursor: T.nilable(String),
      before_cursor: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def get_code_scanning_alerts(campaign, query_string, after_cursor, before_cursor)
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

    {
      alerts: serialized_alerts(alerts:, suggested_fixes: nil, alert_links:),
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      openWithLinksCount: campaign_with_alerts.open_with_links_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }
  end

  sig do
    params(
      campaign: SecurityCampaigns::SecurityCampaign,
      query_string: T.nilable(String),
      after_cursor: T.nilable(String),
      before_cursor: T.nilable(String)
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def get_secret_scanning_alerts(campaign, query_string, after_cursor, before_cursor)
    allowed_repo_ids = repository_ids_from_params_for_secret_scanning
    if allowed_repo_ids.nil?
      allowed_repo_ids = allowed_repo_ids_for_secret_scanning
    end

    per_page = 25
    kwargs = {
      organization: this_organization,
      query: query_string,
      security_campaign_ids: [campaign.id],
      allowed_repository_ids: allowed_repo_ids,
      current_user: current_user,
      user_session: user_session
    }
    alert_service = SecretScanning::AlertQueryService.for_organization(**kwargs)

    alerts, open_alert_count, closed_alert_count, response, request_error = alert_service.get_alerts_with_response(
      after_cursor:,
      before_cursor:,
      per_page: per_page
    )

    next_cursor = T.let(response&.data&.try(:next_cursor), T.nilable(String))
    prev_cursor = T.let(response&.data&.try(:previous_cursor), T.nilable(String))

    # Calculate the number of alerts actually matching the filter
    alert_count = if alert_service.parsed_query.is_open_page?
      open_alert_count
    elsif alert_service.parsed_query.is_closed_page?
      closed_alert_count
    else
      open_alert_count + closed_alert_count
    end

    {
      alerts: SecretScanning::SecurityCampaigns::AlertsSerializer.serialized_alerts(alerts: alerts),
      alertCount: alert_count,
      openCount: open_alert_count,
      closedCount: closed_alert_count,
      nextCursor: next_cursor,
      prevCursor: prev_cursor,
    }
  end
end
