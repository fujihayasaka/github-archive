# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::AlertsController < Repos::SecurityCampaigns::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer
  include ActionView::Helpers::TextHelper

  before_action :check_code_scanning_read, only: [:index]
  before_action :check_code_scanning_write, except: [:index]

  allow_verified_fetch only: [:close, :assign_to_copilot]

  before_action :try_parse_json_params, only: [:close, :assign_to_copilot]

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
    scope = SecurityCampaigns::SecurityCampaign.open
    scope = scope.filter_spam_for(current_user)
    campaign = SecurityCampaigns::SecurityCampaign.open.
        find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil?

    query_string = params[:query].try(:to_str)

    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)


    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session:,
      organization: T.must(campaign.organization),
      security_campaign_ids: [T.must(campaign.id)],
      allowed_repository_ids: [current_repository.id],
      query: query_string,
    )
    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(security_campaign: campaign, query_service:, after_cursor:, before_cursor:)

    return render_404 if campaign_with_alerts.open_count == 0 && campaign_with_alerts.closed_count == 0

    alerts = campaign_with_alerts.turboscan_alerts
    suggested_fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(current_repository, alerts.map(&:result).map(&:number))
    alert_links = CodeScanning::AlertLinks.load(campaign_with_alerts.repo_alert_tuples)

    payload = {
      alerts: serialized_alerts(alerts:, suggested_fixes:, alert_links:),
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      openWithLinksCount: campaign_with_alerts.open_with_links_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }

    render json: payload
  end

  def close # rubocop:todo GitHub/UseRestfulActions
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: current_repository.owner_id)

    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)
    return render status: 422, json: { message: "Campaign is in draft" } if campaign.draft?
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

    return render status: 400, json: { message: "Alert numbers are not valid" } unless alerts_are_in_campaign?(campaign, alert_numbers)

    normalized_dismissal_comment = GitHub::Turboscan.normalize_dismissed_comment(dismissal_comment)
    if CodeScanning::AlertDismissalService.new(current_repository).enabled?
      return render status: 400, json: { message: "Alert dismissal comment is not valid" } if !GitHub::Turboscan.dismissed_request_comment_valid?(normalized_dismissal_comment)

      request_dismissal(current_repository, campaign, alert_numbers, resolution, resolved_resolution, current_user, normalized_dismissal_comment)
    else
      return render status: 400, json: { message: "Alert dismissal comment is not valid" } if !GitHub::Turboscan.dismissed_comment_valid?(normalized_dismissal_comment)

      close_alerts(current_repository, campaign, alert_numbers, resolution, resolved_resolution, current_user, normalized_dismissal_comment)
    end
  end

  def assign_to_copilot # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless SecurityCampaigns.assign_to_copilot_enabled?(current_repository)

    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: current_repository.owner_id)
    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)
    return render status: 422, json: { message: "Campaign is in draft" } if campaign.draft?
    return render status: 422, json: { message: "Campaign is already closed" } if campaign.closed?

    alert_numbers = params[:alert_numbers]
    return render status: 422, json: { message: "Alert numbers are required" } if alert_numbers.blank? || !alert_numbers.is_a?(Array)

    alert_numbers = params[:alert_numbers].map(&:to_i)
    return render status: 422, json: { message: "Invalid alert numbers" } unless alert_numbers.all?(&:positive?)

    default_branch_ref = current_repository.default_branch_ref
    return render status: 422, json: { message: "Default branch must exist" } if default_branch_ref.nil?

    begin
      alerts_with_autofix_suggestions = {}
      CodeScanning::AutofixSuggestion.fetch_applicable_suggested_fix_alerts(
        repository: current_repository,
        alert_numbers:,
        head_commit_oid: default_branch_ref.commit.oid,
        ref_names_bytes: [default_branch_ref.qualified_name.b],
      ).each do |alert_number, suggested_fix_alert|
        # Create the hydro event structure based on the Alert message definition
        alerts_with_autofix_suggestions[alert_number] = {
          alert_number: alert_number,
          suggested_fix: {
            files: suggested_fix_alert.suggested_fix&.files&.map do |fix_file|
              {
                file_path: fix_file.file_path,
                diff_content: fix_file.diff_content
              }
            end || []
          }
        }
      end
    rescue CodeScanning::AutofixError => e
      GitHub.logger.info(
        "Assign to Copilot failed fetching valid autofix suggestions for repo: #{e}",
        "gh.organization.id" => campaign.organization_id,
        "gh.security_campaign.id" => campaign.id,
        "gh.repository.id" => current_repository.id,
      )
    end

    if alerts_with_autofix_suggestions.nil? || alerts_with_autofix_suggestions.empty?
      return render status: 422, json: { message: "No alerts with autofix suggestions found" }
    end

    copilot_swe_agent = T.must(Apps::Privileged.integration(:copilot_swe_agent))

    if current_repository.code_scanning_alert_assignment_enabled?
      request = ::Turboscan::Proto::SetAssigneesForAlertsRequest.new(
        repository_id: current_repository.id,
        alert_numbers: alert_numbers,
        user_ids: [copilot_swe_agent.bot.id],
        operation_type: ::Turboscan::Proto::SetAssigneesForAlertsOperationType::SET_ASSIGNEES_FOR_ALERTS_OPERATION_TYPE_APPEND,
      )

      response = GitHub::Turboscan.set_assignees_for_alerts(request.to_h)

      if response.blank? || response.error.present?
        if response&.error&.code == :not_found
          return render status: 422, json: { message: "Could not find the alerts" }
        end
        return render status: 500, json: { message: "Could not set the assignee" }
      end
    end

    # Emit an analytics event for the alert assignment to Copilot
    GlobalInstrumenter.instrument("code_scanning.alerts_assignment", {
      repository: current_repository,
      security_campaign_id: campaign.id,
      code_scanning_alerts: alerts_with_autofix_suggestions.values,
      actor: current_user,
      assignees: [copilot_swe_agent.bot]
    })

    render json: { message: "Alerts successfully assigned to Copilot and it will create a PR shortly" }
  end

  private

  sig { params(campaign: SecurityCampaigns::SecurityCampaign, alert_numbers: T::Array[Integer]).returns(T::Boolean) }
  def alerts_are_in_campaign?(campaign, alert_numbers)
    query_service = CodeScanning::AlertQueryService.for_organization(
      user: current_user,
      user_session:,
      organization: current_repository.owner,
      allowed_repository_ids: [current_repository.id],
      security_campaign_ids: [T.must(campaign.id)],
      repo_numbers: alert_numbers.map do |number|
        Turboscan::Proto::RepoNumber.new(
          repository_id: current_repository.id,
          number:,
        )
      end
    )
    alert_results, _, _, _, has_error = query_service.alerts_by_repo
    return false if has_error

    alert_results_numbers = alert_results.map { |repo_result| repo_result.result.number }
    Set.new(alert_results_numbers) == Set.new(alert_numbers)
  end

  sig do
    params(
      repo: Repository,
      campaign: SecurityCampaigns::SecurityCampaign,
      alert_numbers: T::Array[Integer],
      resolution: String,
      resolved_resolution: Integer,
      resolver: User,
      resolution_note: T.nilable(String),
    ).void
  end
  def close_alerts(repo, campaign, alert_numbers, resolution, resolved_resolution, resolver, resolution_note)
    # bulk operations still use ref_names
    ref_names_bytes = current_repository.default_branch_ref.qualified_name.b

    set_alerts_status_options = {
      repository_id: current_repository.id,
      resolution: resolved_resolution,
      resolver_id: current_user.id,
      resolver_login: current_user.display_login,
      resolution_note: resolution_note,
      numbers: alert_numbers,
      ref_names_bytes: [ref_names_bytes],
    }

    response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, current_repository)
    if response.blank? || response.error.present?
      return render status: 500, json: { message: "Could not close alerts." }
    end

    alerts_count = alert_numbers.size
    flash[:notice] = "#{alerts_count} #{alerts_count == 1 ? "alert was" : "alerts were"} closed successfully"

    repo.refresh_code_scanning_status(alert_numbers: alert_numbers, refresh_reason: :ui_alert_update)

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

  sig do
    params(
      repo: Repository,
      campaign: SecurityCampaigns::SecurityCampaign,
      alert_numbers: T::Array[Integer],
      resolution: String,
      resolved_resolution: Integer,
      resolver: User,
      resolution_note: T.nilable(String),
    ).void
  end
  def request_dismissal(repo, campaign, alert_numbers, resolution, resolved_resolution, resolver, resolution_note)
    alert_numbers.each do |alert_number|
      begin
        CodeScanning::AlertDismissalService.request_dismissal(
          repository: current_repository,
          requester: current_user,
          alert_number: alert_number,
          resolution: resolved_resolution,
          resolution_note: resolution_note,
          pr_review_thread_id: nil,
          campaign_id: campaign.id,
        )
      rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
        next
      rescue CodeScanning::AlertDismissalService::AlertDismissalError
        return render status: 500, json: { message: "Could not request the dismissal." }
      end
    end

    alerts_count = alert_numbers.size
    flash[:notice] = "#{pluralize(alerts_count, 'alert dismissal was', 'alert dismissals were')} requested successfully"
    analytics_event(
      category: "security_campaigns",
      action: "request_alert_dismissal",
      label: {
        "security_campaign_id": campaign.id,
        "resolution": resolution,
        "alert_numbers_count": alert_numbers.size
      }
    )

    render json: { message: "Dismissal requested successfully" }
  end
end
