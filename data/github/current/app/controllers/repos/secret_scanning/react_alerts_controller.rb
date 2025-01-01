# typed: strict
# frozen_string_literal: true

require "openssl"
require "base64"
require "cgi"

class Repos::SecretScanning::ReactAlertsController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include SecretScanning::Encryption::EncryptedSecretsHelper
  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Errors

  PAGE_SIZE = 25

  stylesheet_bundle "secret-scanning"

  sig { returns(String) }
  def self.react_bundle_name
    "secret-scanning"
  end

  layout "layouts/repository_with_container"

  before_action :login_required
  before_action :parse_json_params
  before_action :require_token_scanning_enabled, except: [:index]
  before_action :check_user_has_view_permission, except: [:resolve, :report]
  before_action :check_user_has_write_permission, only: [:resolve, :report, :create_closure_requests]
  before_action :check_delegated_alert_closures_status, only: [:resolve]
  before_action :require_delegated_alert_closures_enabled, only: [:create_closure_requests]
  skip_before_action :cap_pagination, only: [:index] # Skip pagination being capped at 100 pages on dotcom: app/controllers/application_controller.rb

  allow_verified_fetch only: [
    :resolve,
    :report,
    :timeline,
    :secret_type_options,
    :locations,
    :org_access,
    :validate_token,
    :alert_ai_adversarial_audit,
    :alert_ai_workflow_audit,
    :alert_ai_permission_audit,
    :get_token_permissions,
    :get_suggested_fix,
    :create_closure_requests
  ]

  sig { void }
  def index
    if !self.token_scanning.enabled?
      blankslate_payload_builder = SecretScanning::Models::React::BlankslatePayloadBuilder.new(current_repository, current_user)
      payload = blankslate_payload_builder.blankslate_payload(SecretScanning::Models::React::BlankslateType::Disabled)
      return render_react_app_with_sidebar(payload)
    end

    params[:query] = "is:open" if params[:query].nil?

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, current_user)
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: current_user)
    alerts, open_alert_count, closed_alert_count, service_response, request_error = service.get_alerts(page: current_page, per_page: DEFAULT_PER_PAGE)

    if request_error.present?
      GitHub.logger.error(
        "Unable to fetch secret scanning alerts",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": __method__.to_s,
        "repo.id": current_repository.id,
        "exception.type": "AlertQueryServiceError",
        "exception.message": request_error
      )
      SecretScanning::Util::Stats.track_graceful_failure(env)

      blankslate_payload_builder = SecretScanning::Models::React::BlankslatePayloadBuilder.new(current_repository, current_user)
      payload = blankslate_payload_builder.blankslate_payload(SecretScanning::Models::React::BlankslateType::LoadingFailed)
      return render_react_app_with_sidebar(payload)
    end

    GitHub.dogstats.distribution("secret_scanning.index.page", current_page, tags: ["scope:repository"])

    payload = index_payload_builder.page_payload(
      alerts,
      open_alert_count,
      closed_alert_count,
      params[:query],
      PAGE_SIZE,
      current_page,
      service_response&.data&.has_pending_backfill || false,
      service_response&.data&.has_backfill_scanning_terminal_error || false,
      service_response&.data&.has_backfill_scan_max_candidates || false
    )
    render_react_app_with_sidebar(payload)
  end

  sig { void }
  def show
    alert, service_error = token_scan_result
    return render_service_error if service_error.present?
    return render_404 unless alert.present?

    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, current_user)
    payload = show_payload_builder.page_payload(alert)

    render_react_app(
      payload: payload,
      title: "Secret scanning · #{current_repository.name_with_display_owner}",
      page_data: { container_xl: true, class: "full-width" },
    )
  end

  sig { void }
  def resolve # rubocop:todo GitHub/UseRestfulActions
    ids = Array(params[:id]).take(PAGE_SIZE).map(&:to_i).uniq

    if ids.length == 1
      response, error = alerts_service.get_alert(current_repository, current_user, ids[0], current_page)
      return render_service_error if error.present?
      return render plain: "Unable to resolve token successfully. Token not found.", status: :not_found if response.nil?
    end

    numbers_to_slugs = Array(params[:id_with_slug]).take(PAGE_SIZE).reduce({}) do |acc, num_slug_pair|
      parts = num_slug_pair.split(":", 2)
      acc[parts[0].to_i] = parts[1] if parts.length == 2
      acc
    end

    dismissal_comment = params[:dismissal_comment]
    if dismissal_comment.present? && dismissal_comment.length > 280
      return head :bad_request
    end

    error = alerts_service.resolve_alert(repository: current_repository, user: current_user, numbers: ids, resolution: params[:resolution], dismissal_comment: params[:dismissal_comment], numbers_to_slugs: numbers_to_slugs)

    if error != nil
      return render plain: "Unable to resolve token successfully.", status: :not_found if error.is_a? NotFoundByService
      return render plain: "Unable to resolve token successfully.", status: :unprocessable_entity if error.is_a? UnprocessableEntity

      Failbot.report(UnableToResolveToken.new(error.to_s, current_repository.id, ids), repo_id: current_repository.id)
      return render plain: "Unable to resolve token successfully.", status: :internal_server_error
    end

    head :ok
  end

  sig { void }
  def create_closure_requests # rubocop:todo GitHub/UseRestfulActions
    body = request&.body
    request_body = JSON.parse(body.read)

    closure_request_comment = request_body["closure_request_comment"]

    if !closure_request_comment.present?
      flash[:error] = "Comment is required"
      return head :bad_request
    end

    if closure_request_comment.length > 280
      flash[:error] = "Comment is too long (maximum is 280 characters)"
      return head :bad_request
    end

    resolution = request_body["resolution"]
    if !resolution.present?
      flash[:error] = "Resolution is required"
      return head :bad_request
    end

    if !request_body["id"].present?
      flash[:error] = "Must provide an alert number"
      return head :bad_request
    end

    id = request_body["id"]
    begin
      delegated_alert_closures_service.create_alert_closure_request(current_repository, current_user, id.to_s, resolution, closure_request_comment)
    rescue SecretScanning::Errors::ServiceError
      flash[:error] = "A closure request already exists for this alert."
      return head :bad_request
    end

    head :ok
  end

  sig { void }
  def report # rubocop:todo GitHub/UseRestfulActions
    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?
    return render_404 unless self.token_scanning.one_click_reporting_enabled?(alert)
    set_raw_secret_from_encrypted_secret(alert)
    if alert.raw_secret.nil?
      return render plain: "Unable to report token successfully.", status: :internal_server_error
    end

    metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(alert)

    id = params[:id].to_i
    response = alerts_service.report_alert(repository: current_repository, user: current_user, number: id)

    if response.nil?
      return render plain: "Unable to report token successfully.", status: :internal_server_error
    end

    # Send email to token owner without failing the request if the email fails to send
    begin
      if response.result == :REVOKED # ensure we only send the email if the token was revoked
        raise "Token metadata does not exist" unless metadata.present?

        token_owner = User.find_by(id: metadata.owner_id)
        raise "Token owner does not exist" unless token_owner.present?

        has_alert_access = self.token_scanning.resolve_alerts_allowed?(token_owner, alert.commit_oids)
        alert_number = T.let(has_alert_access ? alert.number : nil, T.nilable(Integer))

        SecretScanningMailer.token_reported(current_repository, token_owner, metadata.name, alert_number).deliver_later
      end
    rescue => e # rubocop:todo Lint/GenericRescue
      GitHub.logger.error(
        "Unable to send report token email",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": __method__.to_s,
        "repo.id": current_repository.id,
        "user.id": token_owner&.id,
        "alert.number": alert.number,
        "exception.message": e.message
      )
    end

    respond_to do |format|
      format.json do
        render json: { data: response }
      end
    end
  end

  sig { void }
  def alert_ai_adversarial_audit # rubocop:todo GitHub/UseRestfulActions
    unless self.token_scanning.ai_assisted_remediation_guidance_enabled?
      return render_404
    end

    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?

    fallback_guidance = "View this token's permissions to get an idea of what an adversary could do with it."
    permissions = if alert.token_type == "GITHUB_TOKEN_V2"
      SecretScanning::Services::GitHubTokenMetadataService.new.get_fgp_permissions(alert)
    else
      SecretScanning::Services::GitHubTokenMetadataService.new.get_patv1_permissions(alert)
    end
    guidance = alerts_service.get_adversarial_audit(permissions, current_user)

    respond_to do |format|
      format.json do
        render json: {
          message: guidance.nil? ? fallback_guidance : guidance
        }
      end
    end
  end

  sig { void }
  def alert_ai_workflow_audit # rubocop:todo GitHub/UseRestfulActions
    unless self.token_scanning.ai_assisted_remediation_guidance_enabled?
      return render_404
    end

    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?

    fallback_guidance = "View audit logs for this token to determine what an adversary could do with it."
    actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(alert, current_user)
    guidance = alerts_service.get_workflow_audit(alert.token_type, actions, current_user)

    respond_to do |format|
      format.json do
        render json: {
          message: guidance.nil? ? fallback_guidance : guidance
        }
      end
    end
  end

  sig { void }
  def get_token_permissions #  rubocop:todo GitHub/UseRestfulActions
    unless self.token_scanning.display_alert_permissions_on_show_page?
      return render_404
    end

    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?
    unless alert.is_classic_or_fine_grained_pat?
      return render plain: "Permissions only available for GitHub token types", status: :internal_server_error
    end

    permissions_collection = if alert.token_type == "GITHUB_TOKEN_V2"
      SecretScanning::Services::GitHubTokenMetadataService.new.get_fgp_permissions(alert)&.to_permissions_collection
    else
      SecretScanning::Services::GitHubTokenMetadataService.new.get_patv1_permissions(alert)&.to_permissions_collection
    end

    respond_to do |format|
      format.json do
        render json: {
          permissions: permissions_collection
        }
      end
    end
  end

  sig { void }
  def alert_ai_permission_audit # rubocop:todo GitHub/UseRestfulActions
    unless self.token_scanning.ai_assisted_remediation_guidance_enabled?
      return render_404
    end

    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?

    fallback_guidance = "View audit log events for this token to see what permissions might be able to be removed."
    actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(alert, current_user)

    permissions = if alert.token_type == "GITHUB_TOKEN_V2"
      SecretScanning::Services::GitHubTokenMetadataService.new.get_fgp_permissions(alert)
    else
      SecretScanning::Services::GitHubTokenMetadataService.new.get_patv1_permissions(alert)
    end
    summary, final_permissions = alerts_service.get_permission_audit(actions, permissions, current_user)

    respond_to do |format|
      format.json do
        render json: {
          summary: summary.nil? ? fallback_guidance : summary,
          permissions: final_permissions,
          fallback: summary.nil?
        }
      end
    end
  end

  sig { void }
  def get_suggested_fix # rubocop:todo GitHub/UseRestfulActions
    unless self.token_scanning.ai_assisted_remediation_guidance_enabled?
      return render_404
    end
    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?
    res = alerts_service.get_autofix_suggestion(current_user, alert.number, alert.repository)
    respond_to do |format|
      format.json do
        render json: {
          diff_lines: res.diff_lines,
          explanation: res.explanation,
          accept_feedback: res.accept_feedback
        }
      end
    end
  end

  sig { void }
  def timeline # rubocop:todo GitHub/UseRestfulActions
    alert, service_error = token_scan_result
    raise service_error if service_error.present?
    return render_404 unless alert.present?

    timeline_response = alerts_service.get_alert_timeline(current_repository, current_user, alert)

    if timeline_response.nil?
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_404
    end

    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, current_user)
    timeline_payload = show_payload_builder.timeline_payload(alert, timeline_response)

    respond_to do |format|
      format.json do
        render json: { timeline: timeline_payload }
      end
    end
  end

  sig { void }
  def secret_type_options # rubocop:todo GitHub/UseRestfulActions
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: current_user)
    result, service_error = service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE)

    if service_error
      return render plain: "Unable to load secret type options.", status: :internal_server_error
    end

    query = params[:query]
    if query.nil?
      query_param = "is:open,closed #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS}"
      generic_results_service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: query_param, current_user: current_user)
      generic_results_types, service_error = generic_results_service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE)

      if service_error
        return render plain: "Unable to load secret type options.", status: :internal_server_error
      end

      result = result + generic_results_types
      query = "is:open"
    end

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, current_user)
    filter_options = index_payload_builder.filter_secret_type_options_payload(query, result)
    respond_to do |format|
      format.json do
        render json: { options: filter_options }
      end
    end
  end

  sig { void }
  def provider_options # rubocop:todo GitHub/UseRestfulActions
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: current_user)
    result, service_error = service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER)

    if service_error
      return render plain: "Unable to load provider options.", status: :internal_server_error
    end

    query = params[:query]
    if query.nil?
      query_param = "is:open,closed #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS}"
      generic_results_service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: query_param, current_user: current_user)
      generic_results_providers, service_error = generic_results_service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER)

      if service_error
        return render plain: "Unable to load secret type options.", status: :internal_server_error
      end

      result = result + generic_results_providers
      query = "is:open"
    end

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, current_user)
    filter_options = index_payload_builder.filter_provider_options_payload(query, result)
    respond_to do |format|
      format.json do
        render json: { options: filter_options }
      end
    end
  end

  sig { void }
  def locations # rubocop:todo GitHub/UseRestfulActions
    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, current_user)
    current_page = params[:page].present? ? params[:page].to_i : 1
    result, service_error = alerts_service.get_alert(current_repository, current_user, params[:id].to_i, current_page)

    unless service_error.nil?
      log_service_error("Unable to fetch secret scanning alert", __method__.to_s, service_error.message, params[:id])

      respond_to do |format|
        format.json do
          render json: { locations: [] }
        end
      end
    end

    locations = show_payload_builder.locations_payload(result)

    respond_to do |format|
      format.json do
        render json: { locations: locations }
      end
    end
  end

  sig { void }
  def org_access # rubocop:todo GitHub/UseRestfulActions
    access_id = params.require(:access_id)
    token_type = params.require(:token_type)
    org = current_repository.organization

    org_access = nil
    if org.present?
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token_type, access_id.to_i, org)
    end
    respond_to do |format|
      format.json do
        render json: { org_access: org_access }
      end
    end
  end

  sig { void }
  def validate_token # rubocop:todo GitHub/UseRestfulActions
    data = nil
    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert.present?

    if alert.on_demand_check_allowed?
      data = alerts_service.validate_token_on_demand(current_repository, current_user, params[:id].to_i)
    end
    respond_to do |format|
      format.json do
        render json: { data: data }
      end
    end
  end

  private

  sig { void }
  def require_token_scanning_enabled
    render_404 unless self.token_scanning.enabled?
  end

  sig { void }
  def require_delegated_alert_closures_enabled
    render_404 unless self.delegated_alert_closures.enabled?
  end

  sig { void }
  def check_user_has_view_permission
    # we bail out early if the user can access the scanning UI, typically as admins someone granted explicit access.
    return if self.token_scanning.view_alerts_allowed?(current_user)

    # we error out if anyone tries to access the index action otherwise, as thats not allowed.
    return render_404 if params[:action] == "index"

    # the code below focuses on making sure the user is a committer and can view any of the committer based endpoints.
    return render_404 unless ::SecretScanning::AccessControl::CommitAuthorView.new(current_repository).has_access_to_repository?(current_user)

    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return render_404 unless alert&.scan_scope == :COMMIT

    # rubocop:todo GitHub/AvoidCast
    render_404 unless alert.present? && T.cast(current_repository, Repository).any_commits_authored_by_user?(current_user, alert.commit_oids)
    # rubocop:enable GitHub/AvoidCast
  end

  sig { void }
  def check_delegated_alert_closures_status
    # If delegated alert closures is disabled, skip the rest of this check.
    return unless self.delegated_alert_closures.enabled?

    # The user should only be able to resolve an alert directly, if they are a valid reviewer.
    render_404 unless SecretScanning::Services::DelegatedAlertClosuresService.is_valid_reviewer?(current_repository, current_user)
  end

  # currently this is only called by the resolve action
  sig { void }
  def check_user_has_write_permission # rubocop:todo GitHub/UseRestfulActions
    # allows users who have write permissions (i.e. those who can see checkboxes on the ACV page and resolve alerts
    # in bulk)
    return if self.token_scanning.resolve_alerts_allowed?(current_user, [])

    ids = Array(params[:id]).take(PAGE_SIZE).map(&:to_i).uniq

    # at this point, the only types of users left are
    #   - secret authors
    #   - those with fine-grained permission to view secret scanning alerts only

    # the array check handles the edge case where
    #   - someone with permissions to resolve alerts navigates to the ACV page. since they have resolve permissions,
    #     they see checkboxes
    #   - while they're on this page, an admin changes their permissions to view alerts only
    #   - they then try to resolve multiple alerts with the checkbox view that has already been rendered for them
    return render_404 if ids.length > 1

    # at this point, the user is possibly a secret author and we will check if they authored the commit that introduced
    # the secret
    params[:id] = ids.first
    alert, service_error = token_scan_result
    return render plain: "Unable to fetch secret scanning alert", status: :internal_server_error if service_error.present?
    return if alert.present? && self.token_scanning.resolve_alerts_allowed?(current_user, alert.commit_oids)

    render_404
  end

  sig { returns(SecretScanning::Features::Repo::TokenScanning) }
  memoize def token_scanning
    SecretScanning::Features::Repo::TokenScanning.new(current_repository)
  end

  sig { returns(SecretScanning::Features::Repo::GenericSecrets) }
  memoize def generic_secrets
    SecretScanning::Features::Repo::GenericSecrets.new(current_repository)
  end

  sig { returns(SecretScanning::Features::Repo::LowerConfidencePatterns) }
  memoize def lower_confidence_patterns
    SecretScanning::Features::Repo::LowerConfidencePatterns.new(current_repository)
  end

  sig { returns(SecretScanning::Features::Repo::DelegatedClosures) }
  memoize def delegated_alert_closures
    SecretScanning::Features::Repo::DelegatedClosures.new(current_repository)
  end

  sig { returns(SecretScanning::Services::AlertsService) }
  memoize def alerts_service
    SecretScanning::Services::AlertsService.new
  end

  sig { returns(SecretScanning::Services::DelegatedAlertClosuresService) }
  memoize def delegated_alert_closures_service
    SecretScanning::Services::DelegatedAlertClosuresService.new
  end

  sig { returns([T.nilable(GitHub::TokenScanning::Service::Token), T.nilable(SecretScanning::Errors::ServiceError)]) }
  memoize def token_scan_result
    related_alerts_enabled = feature_flag_enabled_in_hierarchy?(current_repository, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS) || feature_flag_enabled_in_hierarchy?(current_user, FeatureFlags::SHOW_SINGLE_ALERT_VIEW_RELATED_ALERTS)
    result, service_error = self.alerts_service.get_alert(current_repository, current_user, params[:id].to_i, nil, include_related_alerts: related_alerts_enabled)

    if service_error.present?
      log_service_error("Unable to fetch secret scanning alert", __method__.to_s, service_error.message, params[:id].to_s)
    end

    [result, service_error]
  end

  sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  def render_react_app_with_sidebar(payload)
    title = "Secret scanning · #{current_repository.name_with_display_owner}"
    unless payload[:query].nil?
      title += " (filters applied)" if payload[:query][:filters_applied]
    end

    generic_alerts_available = lower_confidence_patterns.feature_available? || generic_secrets.feature_available?
    parsed_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: params[:query], allow_results_category: generic_alerts_available)
    query_includes_generic_results = parsed_query.results_category == Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS

    layout = "layouts/secret_scanning/sidebar_container"
    if generic_alerts_available && query_includes_generic_results
      layout = "layouts/secret_scanning/sidebar_container_generic_results"
    end

    if payload[:query].nil? && payload[:blankslate_type].nil?
      GitHub.logger.info(
        "Unable to provide secret scanning index query value",
        "code.namespace": self.class.name,
        "code.function": __method__.to_s,
        "controller.name": self.class.name,
        "controller.action": "index",
        "repoid": current_repository,
      )
    end

    render_react_app(
      payload: payload,
      title: title,
      layout: layout,
      page_data: { container_xl: true },
    )
  end

  sig { void }
  def render_service_error
    render_react_app(payload: nil, status: :internal_server_error, title: "Secret scanning · #{current_repository.name_with_display_owner}")
  end

  sig { params(log_msg: String, method_name: String, error_message: String, alert_id: T.nilable(String)).void }
  def log_service_error(log_msg, method_name, error_message, alert_id)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "repo.id": current_repository.id,
      "pattern.id": alert_id,
      "exception.type": SecretScanning::Services::AlertsService::ERROR_TYPE,
      "exception.message": error_message
    )
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index, :show, :timeline, :org_access, :locations, :secret_type_options, :provider_options, :alert_ai_adversarial_audit, :alert_ai_workflow_audit, :alert_ai_permission_audit, :get_token_permissions, :get_suggested_fix]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

end
