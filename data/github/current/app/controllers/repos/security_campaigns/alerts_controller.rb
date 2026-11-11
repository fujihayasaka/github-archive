# typed: true
# frozen_string_literal: true

class Repos::SecurityCampaigns::AlertsController < Repos::SecurityCampaigns::BaseRepositoryController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CodeScanning::AlertsSerializer
  include ActionView::Helpers::TextHelper

  before_action :check_user_has_view_permission, only: [:index]
  before_action :check_user_has_write_permission, except: [:index]

  allow_verified_fetch only: [:assign_to_copilot, :check_for_new_fixes]

  before_action :try_parse_json_params, only: [:assign_to_copilot]

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

    if campaign.alert_type == "secret_scanning"
      return render_404 unless SecretScanning::Features::Repo::TokenScanning.new(current_repository).view_alerts_allowed?(current_user)
      return render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, current_repository, current_repository.owner, current_repository.owner&.business, default: false)
      query_service = SecretScanning::AlertQueryService.for_organization(
        organization: T.must(campaign.organization),
        security_campaign_ids: [T.must(campaign.id)],
        current_user:,
        user_session:,
        allowed_repository_ids: [current_repository.id],
        query: query_string,
      )
    else
      return render_404 unless current_repository.code_scanning_readable_by?(current_user)
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session:,
        organization: T.must(campaign.organization),
        security_campaign_ids: [T.must(campaign.id)],
        allowed_repository_ids: [current_repository.id],
        query: query_string,
      )
    end
    campaign_with_alerts = SecurityCampaigns::CampaignWithAlerts.load_campaign(security_campaign: campaign, query_service:, after_cursor:, before_cursor:)

    return render_404 if campaign_with_alerts.open_count == 0 && campaign_with_alerts.closed_count == 0

    campaign_alerts = campaign_with_alerts.turboscan_alerts

    if campaign.alert_type == "secret_scanning"
      secret_alerts = T.cast(campaign_alerts, T::Array[GitHub::TokenScanning::Service::Token])
      serialized = SecretScanning::SecurityCampaigns::AlertsSerializer.serialized_alerts(alerts: secret_alerts)
      suggested_fixes = {}
      alert_links = {}
    else
      code_scanning_alerts = T.cast(campaign_alerts, T::Array[CodeScanning::AlertResult])
      suggested_fixes = CodeScanning::Autofix.suggested_fixes_for_alerts(current_repository, code_scanning_alerts.map(&:result).map(&:number))
      alert_links = CodeScanning::AlertLinks.load(campaign_with_alerts.repo_alert_tuples)
      serialized = serialized_alerts(alerts: code_scanning_alerts, suggested_fixes: suggested_fixes, alert_links: alert_links)
    end

    payload = {
      alerts: serialized,
      openCount: campaign_with_alerts.open_count,
      closedCount: campaign_with_alerts.closed_count,
      openWithLinksCount: campaign_with_alerts.open_with_links_count,
      nextCursor: campaign_with_alerts.next_cursor,
      prevCursor: campaign_with_alerts.prev_cursor,
    }

    render json: payload
  end

  def assign_to_copilot # rubocop:todo GitHub/UseRestfulActions
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: current_repository.owner_id)
    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)
    if campaign.alert_type == "secret_scanning"
      return render_404 unless SecretScanning::Features::Repo::TokenScanning.new(current_repository).resolve_alerts_allowed?(current_user, [])
      return render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, current_repository, current_repository.owner, current_repository.owner&.business, default: false)
      return render status: 422, json: { message: "Assigning alerts to Copilot is not supported for secret scanning campaigns" }
    end
    return render_404 unless current_repository.code_scanning_writable_by?(current_user)

    return render_404 if !current_repository.copilot_swe_agent_enabled?(current_user)
    return render_404 if !current_repository.owner.feature_flag_enabled?(:copilot_security_alert_assignee_options, default: false)

    return render status: 422, json: { message: "Campaign is in draft" } if campaign.draft?
    return render status: 422, json: { message: "Campaign is already closed" } if campaign.closed?

    alert_numbers = params[:alert_numbers]
    return render status: 422, json: { message: "Alert numbers are required" } if alert_numbers.blank? || !alert_numbers.is_a?(Array)

    alert_numbers = params[:alert_numbers].map(&:to_i)
    return render status: 422, json: { message: "Invalid alert numbers" } unless alert_numbers.all?(&:positive?)

    default_branch_ref = current_repository.default_branch_ref
    return render status: 422, json: { message: "Default branch must exist" } if default_branch_ref.nil?

    # GetAlertTitles twirp endpoint requires an exact length match between the alert numbers and the repository IDs.
    repo_ids = alert_numbers.map { current_repository.id }
    response = GitHub::Turboscan.alert_titles(repository_ids: repo_ids, alert_numbers: alert_numbers)
    alert_titles_map = {}
    if response.present? && response.error.nil? && response.data.present?
      data = T.must(response.data)
      alert_titles_map = data.alert_numbers.zip(data.titles).to_h do |alert_number, title|
        [alert_number, title.present? ? title : "Code scanning alert"]
      end
    end

    alerts_with_autofix_suggestions = CodeScanning::AlertAssignment.build_alerts_assignment_alerts(repository: T.must(current_repository), alert_numbers:, alert_titles: alert_titles_map)

    if alerts_with_autofix_suggestions.nil? || alerts_with_autofix_suggestions.empty?
      return render_404 unless SecretScanning::Features::Repo::TokenScanning.new(current_repository).resolve_alerts_allowed?(current_user, [])
      return render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, current_repository, current_repository.owner, current_repository.owner&.business, default: false)
      return render status: 422, json: { message: "No alerts with autofix suggestions found" }
    end

    copilot_swe_agent = T.must(Apps::Privileged.integration(:copilot_swe_agent))

    request = ::Turboscan::Proto::SetAssigneesForAlertsRequest.new(
      repository_id: current_repository.id,
      alert_numbers: alert_numbers,
      user_ids: [copilot_swe_agent.bot.id],
      operation_type: ::Turboscan::Proto::SetAssigneesForAlertsOperationType::SET_ASSIGNEES_FOR_ALERTS_OPERATION_TYPE_APPEND,
      actor_id: current_user.id,
      actor: current_user.display_login,
      org_id: current_repository.owner_id,
      org: current_repository.owner.display_login,
      business_id: current_repository.owner.business&.id,
      business: current_repository.owner.business&.slug,
      repository_nwo: current_repository.name_with_display_owner
    )

    response = GitHub::Turboscan.set_assignees_for_alerts(request.to_h)

    if response.blank? || response.error.present?
      if response&.error&.code == :not_found
        return render status: 422, json: { message: "Could not find the alerts" }
      end
      return render status: 500, json: { message: "Could not set the assignee" }
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

  def check_for_new_fixes # rubocop:todo GitHub/UseRestfulActions
    campaign = SecurityCampaigns::SecurityCampaign.find_by(number: params[:number], organization: current_repository.owner_id)
    if campaign&.alert_type == "secret_scanning"
      return render_404 unless SecretScanning::Features::Repo::TokenScanning.new(current_repository).resolve_alerts_allowed?(current_user, [])
      return render_404 unless FeatureFlag.vexi.enabled?(:secret_scanning_campaigns, current_user, current_repository, current_repository.owner, current_repository.owner&.business, default: false)
      return render status: 422, json: { message: "Copilot autofixes are not supported for secret scanning campaigns" }
    end
    return render_404 unless current_repository.code_scanning_writable_by?(current_user)

    return render_404 unless CodeScanning::AutofixService.iterative_autofix_regenerate_button_enabled?(current_repository)

    return render_404 if campaign.nil? || campaign.hide_from_user?(current_user)
    return render status: 422, json: { message: "Campaign is in draft" } if campaign.draft?
    return render status: 422, json: { message: "Campaign is already closed" } if campaign.closed?

    default_branch_ref = current_repository.default_branch_ref
    return render status: 422, json: { message: "Default branch must exist" } if default_branch_ref.nil?

    begin
      alert_results = fetch_repository_alert_results(campaign)
    rescue CodeScanning::AutofixError => e
      return render status: e.status, json: { message: "Failed to fetch alerts to include in the campaign. Please reload and try again." }
    end

    return render status: 422, json: { message: "Could not find any alerts to include in the campaign. Please reload and try again." } if alert_results.empty?

    # Convert to the format expected by the job
    logical_alert_info = convert_alert_results_to_job_format(alert_results)
    SecurityCampaigns::GenerateAutofixesJob.perform_later(campaign_id: campaign.id, logical_alert_info:, regenerate: true)

    render json: { message: "We will check for new fixes shortly" }
  end

  private

  # Fetch alerts from repository with proper error handling and guards (similar to AlertResultsHelper)
  def fetch_repository_alert_results(campaign)
    tags = ["kind:turboscan_alerts"]
    GitHub.dogstats.distribution_time("security_campaigns.alerts_for_repo_load", tags: tags) do
      query_service = CodeScanning::AlertQueryService.for_organization(
        user: current_user,
        user_session: user_session,
        organization:  T.must(campaign.organization),
        security_campaign_ids: [T.must(campaign.id)],
        allowed_repository_ids: [current_repository.id]
      )

      alert_results = T.let([], T::Array[CodeScanning::AlertResult])
      cursor = T.let(nil, T.nilable(String))
      requests = 0

      # Guard against infinite loops and apply limits (from AlertResultsHelper)
      while alert_results.size < SecurityCampaigns::MAX_ALERTS_COUNT && requests < SecurityCampaigns::MAX_ALERT_QUERY_REQUEST_COUNT
        page_alert_results, _, has_error, response = query_service.alerts_by_repo_with_response(
          after_cursor: cursor,
          per_page: [SecurityCampaigns::TURBOSCAN_MAX_PAGE_SIZE, SecurityCampaigns::MAX_ALERTS_COUNT - alert_results.size].min,
        )

        raise CodeScanning::AutofixError.new("Failed to fetch alerts from query service", status: :internal_server_error) if has_error

        alert_results.concat(page_alert_results)
        cursor = response.try(:data).try(:next_cursor)

        break if cursor.blank?
        requests += 1
      end

      alert_results
    end
  end

  sig { params(alert_results: T::Array[CodeScanning::AlertResult]).returns(T::Array[{ repo_id: Integer, alerts: T::Array[{ alert_number: Integer, tool_name: String }] }]) }
  def convert_alert_results_to_job_format(alert_results)
    [{
      repo_id: current_repository.id,
      alerts: alert_results.map do |alert_result|
        {
          alert_number: alert_result.result.number,
          tool_name: alert_result.result.tool&.name || "unknown"
        }
      end
    }]
  end

  sig { void }
  def check_user_has_view_permission
    return if SecretScanning::Features::Repo::TokenScanning.new(current_repository).view_alerts_allowed?(current_user) || current_repository.code_scanning_readable_by?(current_user)
    render_404
  end

  sig { void }
  def check_user_has_write_permission
    return if SecretScanning::Features::Repo::TokenScanning.new(current_repository).resolve_alerts_allowed?(current_user, []) || current_repository.code_scanning_writable_by?(current_user)
    render_404
  end
end
