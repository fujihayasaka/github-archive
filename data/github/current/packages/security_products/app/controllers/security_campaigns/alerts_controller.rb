# typed: true
# frozen_string_literal: true

class SecurityCampaigns::AlertsController < SecurityCampaigns::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include SecurityCampaigns::AlertsSerializer

  allow_verified_fetch only: [:close]

  before_action :try_parse_json_params, only: [:close]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Notify,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    only: [:index]

  depends_on_clusters ApplicationRecord::IssuesPullRequests,
    only: [:index],
    optional: true

  def index
    campaign =
      SecurityCampaigns::SecurityCampaign.open.
      for_repo_with_alerts(current_repository).
      find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil?

    query_string = params[:query].try(:to_str)

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(campaign, repo: current_repository, user: current_user, user_session: user_session, query_string:, after_cursor:, before_cursor:)
    alerts = campaign_with_alerts.turboscan_alerts
    suggested_fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(current_repository, alerts.map(&:number))
    alert_links = CodeScanning::AlertLinks.load(campaign_with_alerts.repo_alert_tuples)

    payload = {
      alerts: serialized_alerts(security_campaign: campaign, alerts:, repositories: { current_repository.id => current_repository }, suggested_fixes:, alert_links:),
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }

    render json: payload
  end

  def close # rubocop:todo GitHub/UseRestfulActions
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil?
    return render status: 422, json: { message: "Campaign is already closed" } if campaign.closed?

    alert_numbers = params[:alert_numbers]
    resolution = params[:resolution]
    dismissal_comment = params[:dismissal_comment]

    return render status: 422, json: { message: "Alert numbers are required" } if alert_numbers.blank? || !alert_numbers.is_a?(Array)
    return render status: 422, json: { message: "Resolution reason is required" } if resolution.blank?
    return render status: 422, json: { message: "Default branch must exist" } if current_repository.default_branch_ref.nil?

    alert_numbers = alert_numbers.map(&:to_i)
    return render status: 422, json: { message: "Invalid alert numbers" } unless alert_numbers.all?(&:positive?)

    resolved_resolution = GitHub::Turboscan.to_resolution(resolution)
    return render status: 400, json: { message: "Resolution reason is not valid" } if resolved_resolution.nil?

    normalized_dismissal_comment = GitHub::Turboscan.normalize_dismissed_comment(dismissal_comment)
    return render status: 400, json: { message: "Alert dismissal comment is not valid" } if !GitHub::Turboscan.dismissed_comment_valid?(normalized_dismissal_comment)

    return render status: 400, json: { message: "Alert numbers are not valid" } unless alerts_are_in_campaign?(campaign, alert_numbers)

    # bulk operations still use ref_names
    ref_names_bytes = current_repository.default_branch_ref.qualified_name.b

    set_alerts_status_options = {
      repository_id: current_repository.id,
      resolution: resolved_resolution,
      resolver_id: current_user.id,
      resolution_note: normalized_dismissal_comment,
      numbers: alert_numbers,
      ref_names_bytes: [ref_names_bytes],
    }

    response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options)

    if response.blank? || response.error.present?
      render status: 500, json: { message: "Could not close alerts." }
    else
      alerts_count = alert_numbers.size
      flash[:notice] = "#{alerts_count} #{alerts_count == 1 ? "alert was" : "alerts were"} closed successfully"

      analytics_event(
        category: "security_campaigns",
        action: "close_alerts",
        label: {
          "security_campaign_id": campaign.id,
          "resolution": resolution,
          "alert_numbers_count": alert_numbers.size
        }
      )

      render json: { message: "Alerts closed successfully" }
    end
  end

  private

  def alerts_are_in_campaign?(campaign, alert_numbers)
    campaign_alert_numbers = SecurityCampaigns::SecurityCampaignAlert.
      where(security_campaign_id: campaign.id, repository_id: current_repository.id, logical_alert_number: alert_numbers).
      pluck(:logical_alert_number)

    Set.new(campaign_alert_numbers) == Set.new(alert_numbers)
  end
end
