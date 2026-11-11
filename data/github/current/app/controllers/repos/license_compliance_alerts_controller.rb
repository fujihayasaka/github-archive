# typed: true
# frozen_string_literal: true

class Repos::LicenseComplianceAlertsController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  EVENT_TYPE_OPENED = "opened"
  EVENT_TYPE_REVIEW_REQUESTED = "review_requested"
  EVENT_TYPE_APPEARED_IN_BRANCH = "appeared_in_branch"
  EVENT_TYPE_REVIEW_DENIED = "review_denied"
  EVENT_TYPE_REVIEW_APPROVED = "review_approved"
  EVENT_TYPE_REVIEW_EXPIRED = "review_expired"
  EVENT_TYPE_EXCEPTION_ADDED = "exception_added"
  EVENT_TYPE_LICENSES_ADDED = "licenses_added"
  EVENT_TYPE_CLOSED = "closed"
  EVENT_TYPE_UNKNOWN = "unknown"

  RESOLUTION_UNKNOWN = "unknown"
  RESOLUTION_EXCEPTION_ADDED = "exception_added"
  RESOLUTION_OUTDATED = "outdated"
  RESOLUTION_LICENSES_ADDED = "licenses_added"

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
    ApplicationRecord::Authnd,
    only: [:show]

  allow_verified_fetch only: [:update]
  before_action :ensure_can_view_license_compliance_alerts, only: [:show, :update]
  before_action :try_parse_json_params, only: [:update]
  before_action :set_alert_number, only: [:show, :update]

  class LicenseComplianceAlertRoutePayload < ReactPayload::Base
    def route_id
      "licenseComplianceAlertRoute"
    end

    def initialize(alert, alert_resolution, events, permissions, enterprise, repository, branch_name)
      @alert = alert
      @alert_resolution = alert_resolution
      @events = events
      @permissions = permissions
      @enterprise = enterprise
      @repository = repository
      @branch_name = branch_name
    end

    def payload
      {
        alert: {
          number: @alert.number,
          status: @alert.status,
          resolution: @alert_resolution,
          createdAtIso: @alert.created_at.to_time.utc.iso8601,
          manifestName: @alert.manifest_name,
          packageEcosystem: DependencyReviewHelper::ECOSYSTEM_MAPPINGS_HUMAN_NAMES[@alert.package_ecosystem] || @alert.package_ecosystem.to_s.downcase,
          packageName: @alert.package_name,
          packageVersion: @alert.package_version,
          license: @alert.license,
          closureReason: DependencyGraph::LicenseComplianceDismissalOptions.label_for_closure_reason(@alert.closure_reason),
          branchName: @branch_name,
          events: @events,
          externalPackageManagerUrl: external_package_manager_url(@alert),
          packageRepositoryUrl: package_repository_url(@alert)
        },
        enterpriseName: @enterprise.name,
        repoLicensePolicyPath: UrlHelpers.repository_license_policy_path(@repository.owner_display_login, @repository),
        dismissalOptions: DependencyGraph::LicenseComplianceDismissalOptions::DISMISSAL_OPTIONS,
        permissions: @permissions
      }
    end

    private

    sig { params(alert: OSSLicenseCompliance::V0::Alert).returns(T.nilable(String)) }
    def external_package_manager_url(alert)
      package_manager = alert.package_ecosystem.to_s.sub("PACKAGE_MANAGER_", "")
      DependencyGraph::PackageUrlBuilder.external_url(
        package_manager: package_manager,
        package_name: alert.package_name
      )&.to_s
    end

    sig { params(alert: OSSLicenseCompliance::V0::Alert).returns(T.nilable(String)) }
    def package_repository_url(alert)
      # Only resolve package repository URLs on dotcom - GHES and Proxima may have
      # repos with the same nwo that are different from the dotcom source repo
      # We will revisit when we work on https://github.com/github/dependency-graph/issues/9610
      return nil if GitHub.enterprise? || GitHub.multi_tenant_enterprise?
      return nil if alert.package_repo_nwo.blank?

      Repository.with_name_with_owner(alert.package_repo_nwo)&.permalink
    end
  end

  def show
    response = fetch_alert
    return render_404 if response.alert.nil?

    alert = T.must(response.alert)

    # Sync expired dismissal request with OLC if one exists
    synced_response = sync_expired_dismissal_request_with_olc(alert)
    if synced_response
      alert = synced_response.alert
      response = synced_response
    end

    permissions = {
      canRequestLicenseComplianceAlertDismissal: Permissions::LicensePolicy.can_request_license_compliance_alert_dismissal?(current_user, @current_repository),
      canManageEnterpriseLicensePolicy: Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business),
      canManageRepositoryLicensePolicy: Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, @current_repository),
      # TODO: Remove canReviewLicenseComplianceAlertDismissalRequest and useNewLicensePolicyPermissions once the dependency_graph_eoslm_switch feature flag is removed.
      useNewLicensePolicyPermissions: FeatureFlag.vexi.enabled?(:dependency_graph_eoslm_switch, @current_repository, @current_repository.organization, @current_repository.business, default: false),
      canReviewLicenseComplianceAlertDismissalRequest: Permissions::LicensePolicy.can_review_license_compliance_alert_dismissal_request?(current_user, @current_repository),
    }

    respond_with_react(
      app_name: "license-compliance-alerts",
      payload: LicenseComplianceAlertRoutePayload.new(
        alert,
        resolution_to_string(alert&.resolution),
        build_events(response.events, alert),
        permissions,
        @current_repository.business,
        @current_repository,
        pull_request&.head_ref
      ),
      title: "License Compliance Alert",
      page_data: { selected_link: :security },
    )
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render_404
  end

  def update
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
  rescue OSSLicenseCompliance::Twirp::InvalidSPDXExpressionError => err
    Failbot.report(err)
    render json: { error: err.msg }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::InvalidSPDXIdentifiersError => err
    Failbot.report(err)
    render json: { error: err.msg }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::InvalidArgumentError => err
    Failbot.report(err)
    render json: { error: "Invalid request parameters" }, status: :bad_request
  rescue OSSLicenseCompliance::Twirp::PreconditionFailedError => err
    Failbot.report(err)
    render json: { error: "Invalid preconditions" }, status: :precondition_failed
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    Failbot.report(err)
    render json: { error: "Failed to update the alert" }, status: :internal_server_error
  end

  private

  sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
  memoize def license_compliance_client
    OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
  end

  sig { params(policy_level: Symbol).returns(T::Boolean) }
  def can_manage_for_policy_level?(policy_level)
    if policy_level == :POLICY_LEVEL_ENTERPRISE
      Permissions::LicensePolicy.can_manage_enterprise_license_policy?(current_user, @current_repository.business)
    else
      Permissions::LicensePolicy.can_manage_repository_license_policy?(current_user, @current_repository)
    end
  end

  sig { void }
  def set_alert_number
    @alert_number = params[:number].to_i

    render_404 if @alert_number <= 0
  end

  def request_dismissal
    return render json: { error: "Forbidden" }, status: :forbidden unless Permissions::LicensePolicy.can_request_license_compliance_alert_dismissal?(current_user, @current_repository)

    request_params = {
      repository_id: @current_repository.id,
      number: @alert_number,
      user_id: current_user.id
    }
    reason = params[:reason].to_s
    unless DependencyGraph::LicenseComplianceDismissalOptions.valid_dismissal_reason?(reason)
      return render json: { error: "Invalid request parameters: reason is missing or unsupported." }, status: :bad_request
    end

    closure_reason = DependencyGraph::LicenseComplianceDismissalOptions.closure_reason_for(reason)
    if closure_reason.nil?
      return render json: { error: "Invalid request parameters: reason is missing or unsupported." }, status: :bad_request
    end

    request_params[:closure_reason] = closure_reason
    request_params[:comment] = params[:comment]

    license_compliance_client.request_alert_dismissal(**request_params)

    render json: { success: true }
  end

  def deny_dismissal
    return render json: { error: "Forbidden" }, status: :forbidden unless Permissions::LicensePolicy.can_review_license_compliance_alert_dismissal_request?(current_user, @current_repository)

    license_compliance_client.deny_alert_dismissal(
      comment: params[:comment],
      number: @alert_number,
      repository_id: @current_repository.id,
      user_id: current_user.id
    )

    render json: { success: true }
  end

  def create_exception
    policy_level = params[:policy_level]&.to_sym
    return render json: { error: "Invalid request parameters: policy_level is required." }, status: :bad_request unless policy_level
    return render json: { error: "Forbidden" }, status: :forbidden unless can_manage_for_policy_level?(policy_level)

    if params[:pattern].present?
      return render json: { error: "Invalid pattern format" }, status: :bad_request unless valid_package_pattern?(params[:pattern])
    end

    request_params = {
      repository_id: @current_repository.id,
      enterprise_id: @current_repository.business.id,
      alert_number: @alert_number,
      user_id: current_user.id,
      policy_level: policy_level,
      # Note: Currently, we only support "distributed" context.
      contexts: ["distributed"],
      comment: params[:comment],
      action: params[:package_action]&.to_sym,
      pattern: params[:pattern],
    }

    if params[:closure_reason].present?
      reason = params[:closure_reason].to_s
      closure_reason = DependencyGraph::LicenseComplianceDismissalOptions.closure_reason_for(reason)
      request_params[:closure_reason] = closure_reason if closure_reason
    end

    license_compliance_client.create_package_exception(**request_params)

    render json: { success: true }
  end

  def add_licenses_for_alert
    policy_level = params[:policy_level]&.to_sym
    return render json: { error: "Invalid request parameters: policy_level is required." }, status: :bad_request unless policy_level
    return render json: { error: "Forbidden" }, status: :forbidden unless can_manage_for_policy_level?(policy_level)

    request_params = {
      alert_number: @alert_number,
      user_id: current_user.id,
      policy_level: policy_level,
      # Note: Currently, we only support "distributed" context.
      contexts: ["distributed"],
      repository_id: @current_repository.id,
      enterprise_id: @current_repository.business.id,
      comment: params[:comment],
    }

    if params[:closure_reason].present?
      reason = params[:closure_reason].to_s
      closure_reason = DependencyGraph::LicenseComplianceDismissalOptions.closure_reason_for(reason)
      request_params[:closure_reason] = closure_reason if closure_reason
    end

    license_compliance_client.add_licenses_for_alert(**request_params)

    render json: { success: true }
  end

  def build_events(proto_events, alert)
    # Use memoized pull_request method to avoid duplicate queries
    pr = pull_request

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
    branch_event = create_synthetic_branch_event(alert, pr) if pr&.head_ref

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
      # TODO: package_name and package_version are being removed from the frontend.
      # Once the github-ui change is deployed, these can be omitted from the event body.
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
  def create_synthetic_branch_event(alert, pr)
    {
      id: "branch-#{@alert_number}",
      alertId: alert.id,
      type: EVENT_TYPE_APPEARED_IN_BRANCH,
      userId: 0, # No user for this event
      occurredAt: alert.created_at.to_time.iso8601,
      eventBody: {
        branch_name: pr.head_ref,
        pull_request_number: pr.number,
        pull_request_title: pr.title,
      }.to_json,
      actor: nil # No actor for branch events
    }
  end

  def event_type_to_string(event_type)
    case event_type
    when :ALERT_EVENT_TYPE_REVIEW_REQUESTED then EVENT_TYPE_REVIEW_REQUESTED
    when :ALERT_EVENT_TYPE_REVIEW_DENIED then EVENT_TYPE_REVIEW_DENIED
    when :ALERT_EVENT_TYPE_REVIEW_APPROVED then EVENT_TYPE_REVIEW_APPROVED
    when :ALERT_EVENT_TYPE_REVIEW_EXPIRED then EVENT_TYPE_REVIEW_EXPIRED
    when :ALERT_EVENT_TYPE_EXCEPTION_ADDED then EVENT_TYPE_EXCEPTION_ADDED
    when :ALERT_EVENT_TYPE_LICENSES_ADDED then EVENT_TYPE_LICENSES_ADDED
    when :ALERT_EVENT_TYPE_CLOSED then EVENT_TYPE_CLOSED
    else EVENT_TYPE_UNKNOWN
    end
  end

  # Syncs an expired dismissal request with OLC if one exists for the given alert.
  sig { params(alert: OSSLicenseCompliance::V0::Alert).returns(T.nilable(OSSLicenseCompliance::V0::GetAlertResponse)) }
  def sync_expired_dismissal_request_with_olc(alert)
    # Only sync if alert is in review_requested state
    return nil unless alert.status == :ALERT_STATUS_REVIEW_REQUESTED

    exemption_request = Exemptions::ExemptionRequest.where(
      request_type: DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
      resource_owner_type: "Repository",
      resource_owner_id: @current_repository.id,
      resource_identifier: alert.id.to_s,
      status: "pending"
    ).order(created_at: :desc).first

    # If no request or request isn't expired, nothing to sync
    return nil unless exemption_request&.expired?

    response = license_compliance_client.expire_alert_dismissal(
      repository_id: @current_repository.id,
      number: @alert_number,
      expiry_timestamp: Google::Protobuf::Timestamp.new(seconds: exemption_request.expires_at.to_i)
    )

    GitHub.instrument("license_compliance_closure_request.sync_expired", {
      actor: current_user,
      repo: @current_repository,
      org: @current_repository.organization,
      alert_number: @alert_number,
      exemption_request_id: exemption_request.id,
      expires_at: exemption_request.expires_at,
    })

    response
  rescue OSSLicenseCompliance::Twirp::PreconditionFailedError => err
    # This can happen if the alert state doesn't allow expiration (race condition)
    # Log but don't fail the page load - user will see the alert in its current state
    Failbot.report(err, {
      alert_number: @alert_number,
      repository_id: @current_repository.id,
      exemption_request_id: exemption_request&.id,
    })
    nil
  rescue OSSLicenseCompliance::Twirp::BaseError => err
    # General error - log but don't fail the page load
    Failbot.report(err, {
      alert_number: @alert_number,
      repository_id: @current_repository.id,
      exemption_request_id: exemption_request&.id,
    })
    nil
  end

  def resolution_to_string(resolution)
    case resolution
    when :ALERT_RESOLUTION_EXCEPTION_ADDED then RESOLUTION_EXCEPTION_ADDED
    when :ALERT_RESOLUTION_OUTDATED then RESOLUTION_OUTDATED
    when :ALERT_RESOLUTION_LICENSES_ADDED then RESOLUTION_LICENSES_ADDED
    else RESOLUTION_UNKNOWN
    end
  end

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull_request
    alert = fetch_alert.alert
    return nil unless alert&.pull_request_number

    repository = Repository.find_by(id: alert.repository_id)
    return nil unless repository

    PullRequest.with_number_and_repo(alert.pull_request_number, repository)
  end

  sig { returns(OSSLicenseCompliance::V0::GetAlertResponse) }
  memoize def fetch_alert
    license_compliance_client.get_alert(repository_id: @current_repository.id, number: @alert_number)
  end

  # Allow alphanumeric, hyphens, underscores, slashes, dots, @, colons, and * wildcard
  sig { params(pattern: String).returns(T::Boolean) }
  def valid_package_pattern?(pattern)
    pattern.match?(/\A[@a-zA-Z0-9_\-.:\/\*]+\z/)
  end

  sig { void }
  def ensure_can_view_license_compliance_alerts
    return if Permissions::LicensePolicy.can_view_license_compliance_alerts?(current_user, current_repository)

    if action_name == "show"
      render_404
    else
      render json: { error: "Not Found" }, status: :not_found
    end
  end
end
