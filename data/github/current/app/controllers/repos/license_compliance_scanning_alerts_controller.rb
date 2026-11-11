# typed: true
# frozen_string_literal: true

class Repos::LicenseComplianceScanningAlertsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  EVENT_TYPE_OPENED = "opened"
  EVENT_TYPE_REVIEW_REQUESTED = "review_requested"
  EVENT_TYPE_APPEARED_IN_BRANCH = "appeared_in_branch"
  EVENT_TYPE_REVIEW_DENIED = "review_denied"
  EVENT_TYPE_REVIEW_APPROVED = "review_approved"
  EVENT_TYPE_EXCEPTION_ADDED = "exception_added"
  EVENT_TYPE_LICENSES_ADDED = "licenses_added"
  EVENT_TYPE_CLOSED = "closed"
  EVENT_TYPE_UNKNOWN = "unknown"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Iam,
    only: [:show]

  allow_verified_fetch only: [:update]
  before_action :try_parse_json_params, only: [:update]
  before_action :set_alert_number

  class LicenseComplianceAlertRoutePayload < ReactPayload::Base
    def route_id
      "licenseComplianceAlertRoute"
    end

    def initialize(alert, events, permissions, enterprise, repository)
      @alert = alert
      @events = events
      @permissions = permissions
      @enterprise = enterprise
      @repository = repository
    end

    def payload
      {
        alert: {
          number: @alert.number,
          status: @alert.status,
          createdAt: @alert.created_at.to_time.strftime("%b %d"),
          manifestName: @alert.manifest_name,
          packageEcosystem: DependencyReviewHelper::ECOSYSTEM_MAPPINGS[@alert.package_ecosystem] || @alert.package_ecosystem.to_s.downcase,
          packageName: @alert.package_name,
          packageVersion: @alert.package_version,
          license: @alert.license,
          events: @events
        },
        enterpriseName: @enterprise.name,
        enterpriseLicenseAlertsPath: @permissions[:canManageEnterpriseLicensePolicy] ? UrlHelpers.enterprise_security_center_bypass_requests_license_compliance_index_path(@enterprise) : nil,
        repoLicensePolicyPath: UrlHelpers.repository_license_policy_path(@repository.owner_display_login, @repository),
        permissions: @permissions
      }
    end
  end

  def show
    return render_404 unless Permissions::LicensePolicy.is_license_compliance_enabled?(@current_repository.business)

    response = fetch_alert
    return render_404 if response.alert.nil?

    permissions = {
      canWriteRepo: current_user_can_write_to_repo?,
      canManageEnterpriseLicensePolicy: Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business)
    }

    respond_with_react(
      app_name: "license-compliance-alerts",
      payload: LicenseComplianceAlertRoutePayload.new(
        response.alert,
        build_events(response.events, response.alert),
        permissions,
        @current_repository.business,
        @current_repository
      ),
      title: "License Compliance Alert",
      page_data: { selected_link: :security },
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  def update
    return render json: { error: "Feature not enabled" }, status: :not_found unless Permissions::LicensePolicy.is_license_compliance_enabled?(@current_repository.business)

    case params[:operation]
    when "request_dismissal"
      request_dismissal
    when "deny_dismissal"
      deny_dismissal
    when "create_exception"
      create_exception
    when "add_licenses_for_alert"
      add_licenses_for_alert
    else
      render json: { error: "Invalid operation" }, status: :bad_request
    end
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: err }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { void }
  def set_alert_number
    @alert_number = params[:number].to_i

    render_404 if @alert_number <= 0
  end

  def request_dismissal
    return render json: { error: "Forbidden" }, status: :forbidden unless current_user_can_write_to_repo?

    license_compliance_client.request_alert_dismissal(
      repository_id: @current_repository.id,
      number: @alert_number,
      user_id: current_user.id
    )

    render json: { success: true }
  end

  def deny_dismissal
    return render json: { error: "Forbidden" }, status: :forbidden unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business)

    license_compliance_client.deny_alert_dismissal(
      comment: params[:comment],
      number: @alert_number,
      repository_id: @current_repository.id,
      user_id: current_user.id
    )

    # Post the reply after denying
    alert = fetch_alert.alert
    post_denied_dismissal_reply(alert)

    render json: { success: true }
  end

  def create_exception
    return render json: { error: "Forbidden" }, status: :forbidden unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business)

    if params[:pattern].present?
      return render json: { error: "Invalid pattern format" }, status: :bad_request unless valid_package_pattern?(params[:pattern])
    end

    license_compliance_client.create_package_exception(
      repository_id: @current_repository.id,
      enterprise_id: @current_repository.business.id,
      alert_number: @alert_number,
      user_id: current_user.id,
      policy_level: params[:policy_level].to_sym,
      # Note: Currently, we only support "distributed" context.
      contexts: ["distributed"],
      comment: params[:comment],
      action: params[:package_action]&.to_sym,
      pattern: params[:pattern]
    )

    render json: { success: true }
  end

  def add_licenses_for_alert
    return render json: { error: "Forbidden" }, status: :forbidden unless Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business)

    response = license_compliance_client.add_licenses_for_alert(
      alert_number: @alert_number,
      user_id: current_user.id,
      policy_level: params[:policy_level].to_sym,
      # Note: Currently, we only support "distributed" context.
      contexts: ["distributed"],
      repository_id: @current_repository.id,
      enterprise_id: @current_repository.business.id,
      comment: params[:comment],
    )

    render json: { success: true }
  end

  def build_events(proto_events, alert)
    # Fetch PR if alert has one (for enriching review_requested events)
    repository = Repository.find_by(id: alert.repository_id)
    pr = PullRequest.with_number_and_repo(alert.pull_request_number, repository) if alert.pull_request_number && repository

    olc_events = (proto_events || []).each_with_object([]) do |event, events|
      user = User.find_by(id: event.user_id) if event.user_id&.positive?

      # If user_id is not set (0 or nil), use license compliance bot
      if !event.user_id&.positive?
        user = Apps::Privileged.attribution_only_system_identity_for(:license_compliance)
      end

      event_body = event.event_body
      if event_type_to_string(event.event_type) == EVENT_TYPE_REVIEW_REQUESTED && pr
        # Parse existing JSON, add PR info, re-serialize
        parsed_body = JSON.parse(event_body || "{}") rescue {}
        parsed_body["pull_request_number"] = pr.number
        parsed_body["pull_request_title"] = pr.title
        event_body = parsed_body.to_json
      end

      actor = nil
      if user.present?
        actor = {
          login: user.display_login,
          avatarUrl: user.primary_avatar_url,
          url: "/#{user.display_login}"
        }
      end

      events << {
        id: event.id,
        alertId: event.alert_id,
        type: event_type_to_string(event.event_type),
        userId: event.user_id,
        occurredAt: event.occurred_at.to_time.iso8601,
        eventBody: event_body, # Pass through as-is (JSON string from Go), enriched for review_requested
        actor: actor,
      }
    end

    # Add synthetic "opened" event at the beginning
    synthetic_opened_event = create_synthetic_opened_event(alert)

    # Add synthetic "appeared_in_branch" event if we have a branch name
    branch_event = create_synthetic_branch_event(alert, pr.head_ref) if pr&.head_ref

    # Return opened event first, then branch event (if exists), then all OLC events (sorted by occurred_at)
    events = [synthetic_opened_event]
    events << branch_event if branch_event
    events + olc_events.sort_by { |e| e[:occurredAt] }
  end

  def create_synthetic_opened_event(alert)
    # Get the bot that creates license compliance alerts
    # In future we could add this to an event in OLC created on alert opening
    bot = Apps::Privileged.attribution_only_system_identity_for(:license_compliance)

    {
      id: "opened-#{@alert_number}",
      alertId: alert.id,
      type: EVENT_TYPE_OPENED,
      userId: bot.id,
      occurredAt: alert.created_at.to_time.iso8601,
      eventBody: {
        package_name: alert.package_name,
        package_version: alert.package_version,
        license: alert.license
      }.to_json,
      actor: {
        login: bot.display_login,
        avatarUrl: bot.primary_avatar_url,
        url: "/#{bot.display_login}"
      }
    }
  end

  # Used to render the "appeared in branch" event
  def create_synthetic_branch_event(alert, branch_name)
    {
      id: "branch-#{@alert_number}",
      alertId: alert.id,
      type: EVENT_TYPE_APPEARED_IN_BRANCH,
      userId: 0, # No user for this event
      occurredAt: alert.created_at.to_time.iso8601,
      eventBody: {
        branch_name: branch_name
      }.to_json,
      actor: nil # No actor for branch events
    }
  end

  def event_type_to_string(event_type)
    case event_type
    when :ALERT_EVENT_TYPE_REVIEW_REQUESTED then EVENT_TYPE_REVIEW_REQUESTED
    when :ALERT_EVENT_TYPE_REVIEW_DENIED then EVENT_TYPE_REVIEW_DENIED
    when :ALERT_EVENT_TYPE_REVIEW_APPROVED then EVENT_TYPE_REVIEW_APPROVED
    when :ALERT_EVENT_TYPE_EXCEPTION_ADDED then EVENT_TYPE_EXCEPTION_ADDED
    when :ALERT_EVENT_TYPE_LICENSES_ADDED then EVENT_TYPE_LICENSES_ADDED
    when :ALERT_EVENT_TYPE_CLOSED then EVENT_TYPE_CLOSED
    else EVENT_TYPE_UNKNOWN
    end
  end

  def post_denied_dismissal_reply(alert)
    return unless alert.present? && alert.pull_request_number.present?

    repository = Repository.find_by(id: alert.repository_id)
    pr = PullRequest.with_number_and_repo(alert.pull_request_number, repository) if repository
    return unless pr

    reply_body = "#{current_user.display_login} denied request to close"
    LicenseCompliance::PrCommentsManager.post_reply_to_comment(pr, alert.id, reply_body)
  end

  sig { returns(OSSLicenseCompliance::V0::GetAlertResponse) }
  memoize def fetch_alert
    license_compliance_client.get_alert(repository_id: @current_repository.id, number: @alert_number)
  end

  # Allow alphanumeric, hyphens, underscores, slashes, dots, @, and * wildcard
  sig { params(pattern: String).returns(T::Boolean) }
  def valid_package_pattern?(pattern)
    pattern.match?(/\A[@a-zA-Z0-9_\-.\/\*]+\z/)
  end
end
