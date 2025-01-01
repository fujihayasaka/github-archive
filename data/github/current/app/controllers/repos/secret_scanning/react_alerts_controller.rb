# typed: strict
# frozen_string_literal: true

require "openssl"
require "base64"
require "cgi"

class Repos::SecretScanning::ReactAlertsController < AbstractRepositoryController # rubocop:todo GitHub/ControllersShouldHaveTests
  extend T::Sig
  include ApplicationController::VerifiedFetchDependency
  include SecretScanning::Encryption::EncryptedSecretsHelper

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
    only: [:index, :show, :alert_autofix, :alert_ai_activity_audit, :timeline, :org_access, :locations, :secret_type_options, :provider_options, :secure_storage]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show],
    optional: true

  include ReactHelper
  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Errors

  javascript_bundle :scanning

  track_latency_slo "uptime-p75-page-index-repo", 3000, only: [:index]
  track_latency_slo "uptime-p75-page-show", 3000, only: [:show]

  # TODO deprecated; refactor in later PRs after monitors have been migrated
  track_latency_slo "p99-ui-request-index-repo", 1000, only: [:index]
  track_latency_slo "p50-ui-request-index-repo", 400, only: [:index]
  track_latency_slo "p99-ui-request-show", 2000, only: [:show]
  track_latency_slo "p50-ui-request-show", 600, only: [:show]

  PAGE_SIZE = 25

  sig { returns(String) }
  def self.react_bundle_name
    "secret-scanning"
  end

  layout "layouts/repository_with_container"

  before_action :login_required
  before_action :require_token_scanning_enabled, except: [:index]
  before_action :check_user_has_view_permission, except: [:resolve, :report]
  before_action :check_user_has_write_permission, only: [:resolve, :report]
  skip_before_action :cap_pagination, only: [:index] # Skip pagination being capped at 100 pages on dotcom: app/controllers/application_controller.rb

  allow_verified_fetch only: [:resolve, :report, :timeline, :secret_type_options, :locations, :org_access, :validate_token, :alert_autofix, :alert_ai_activity_audit, :secure_storage]

  sig { void }
  def index
    if !self.token_scanning.enabled?
      blankslate_payload_builder = SecretScanning::Models::React::BlankslatePayloadBuilder.new(current_repository, T.must(current_user))
      payload = blankslate_payload_builder.blankslate_payload(SecretScanning::Models::React::BlankslateType::Disabled)
      return render_react_app_with_sidebar(payload)
    end

    params[:query] = "is:open" if params[:query].nil?

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, T.must(current_user))
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: T.must(current_user))
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

      blankslate_payload_builder = SecretScanning::Models::React::BlankslatePayloadBuilder.new(current_repository, T.must(current_user))
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
    if !token_scan_result.present?
      # This is a legitimate scenario and we are working as expected, so we count it as a success.
      success = true
      return render_404
    end

    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, T.must(current_user))
    payload = show_payload_builder.page_payload(token_scan_result)

    render_react_app(
      payload: payload,
      title: "Secret scanning · #{current_repository.name_with_display_owner}",
      page_data: { container_xl: true, class: "full-width" },
      ssr: true
    )
  end

  sig { void }
  def resolve # rubocop:todo GitHub/UseRestfulActions
    ids = Array(params[:id]).take(PAGE_SIZE).map(&:to_i).uniq
    numbers_to_slugs = Array(params[:id_with_slug]).take(PAGE_SIZE).reduce({}) do |acc, num_slug_pair|
      parts = num_slug_pair.split(":", 2)
      acc[parts[0].to_i] = parts[1] if parts.length == 2
      acc
    end

    error = alerts_service.resolve_alert(repository: current_repository, user: T.must(current_user), numbers: ids, resolution: params[:resolution], dismissal_comment: params[:dismissal_comment], numbers_to_slugs: numbers_to_slugs)

    if error != nil
      return render plain: "Unable to resolve token successfully.", status: :unprocessable_entity if error.is_a? UnprocessableEntity

      Failbot.report(UnableToResolveToken.new(error.to_s, current_repository.id, ids), repo_id: current_repository.id)
      return render plain: "Unable to resolve token successfully.", status: :internal_server_error
    end

    current_repository.token_scanning_service_unresolved_cache(current_user).bump

    head :ok
  end

  sig { void }
  def report # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless token_scan_result.present?
    return render_404 unless self.token_scanning.one_click_reporting_enabled?(T.must(token_scan_result))

    id = params[:id].to_i
    error = alerts_service.report_alert(repository: current_repository, user: T.must(current_user), number: id)

    if error != nil
      Failbot.report(UnableToReportToken.new(error.to_s, current_repository.id, id), repo_id: current_repository.id)
      return render plain: "Unable to report token successfully.", status: :unprocessable_entity if error.is_a? UnprocessableEntity
      return render plain: "Unable to report token successfully.", status: :internal_server_error
    end

    head :ok
  end

  sig { void }
  def alert_ai_activity_audit # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless SecretScanning::Features::Repo::Autofix.new(current_repository).enabled?

    result = token_scan_result
    if result.nil?
      return render_404
    end

    md_service = SecretScanning::Services::GitHubTokenMetadataService.new
    actions = md_service.get_patv2_recent_actions(result, T.must(current_user))
    permissions = md_service.get_patv2_permissions(result)
    explanation = "No permission found. No recent activity found"
    if actions.length > 0 || permissions.length > 0
      explanation = alerts_service.get_alert_activity_ai_audit(actions, permissions, T.must(current_user))
    end

    respond_to do |format|
      format.json do
        render json: {
          permissions: permissions,
          actions: actions,
          llm_res: explanation
        }
      end
    end
  end

  sig { void }
  def alert_autofix # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless SecretScanning::Features::Repo::Autofix.new(current_repository).enabled?

    result = token_scan_result
    if result.nil?
      return render_404
    end

    response = alerts_service.get_generated_alert_autofix(current_repository, T.must(current_user), result)
    return render_404 if response.nil?

    respond_to do |format|
      format.json do
        render json: {
          original_code_fragment: response.original_code_fragment,
          suggested_code_fragment: response.suggested_code_fragment,
          explanation: response.fix_explanation,
          changed_diff_lines: response.changed_diff_lines,
        }
      end
    end
  end

  sig { void }
  def secure_storage # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless SecretScanning::Features::Repo::Autofix.new(current_repository).enabled?

    response = alerts_service.get_secure_storage_steps(current_repository, T.must(current_user))
    return render_404 if response.nil?

    respond_to do |format|
      format.json do
        render json: {
          message: response,
        }
      end
    end
  end

  sig { void }
  def timeline # rubocop:todo GitHub/UseRestfulActions
    result = token_scan_result
    if result.nil?
      # This is a legitimate scenario and we are working as expected, so we count it as a success.
      success = true
      return render_404
    end

    timeline_response = alerts_service.get_alert_timeline(current_repository, T.must(current_user), result)

    if timeline_response.nil?
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_404
    end

    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, T.must(current_user))
    timeline_payload = show_payload_builder.timeline_payload(result, timeline_response)

    respond_to do |format|
      format.json do
        render json: { timeline: timeline_payload }
      end
    end
  end

  sig { void }
  def secret_type_options # rubocop:todo GitHub/UseRestfulActions
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: T.must(current_user))
    result, service_error = service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE)

    if service_error
      return render plain: "Unable to load secret type options.", status: :internal_server_error
    end

    query = params[:query]
    if query.nil?
      other_confidence_service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: "is:open,closed confidence:other", current_user: T.must(current_user))
      other_confidence_result, service_error = other_confidence_service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE)

      if service_error
        return render plain: "Unable to load secret type options.", status: :internal_server_error
      end

      result = result + other_confidence_result
      query = "is:open"
    end

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, T.must(current_user))
    filter_options = index_payload_builder.filter_secret_type_options_payload(query, result)
    respond_to do |format|
      format.json do
        render json: { options: filter_options }
      end
    end
  end


  sig { void }
  def provider_options # rubocop:todo GitHub/UseRestfulActions
    service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: params[:query], current_user: T.must(current_user))
    result, service_error = service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER)

    if service_error
      return render plain: "Unable to load provider options.", status: :internal_server_error
    end

    query = params[:query]
    if query.nil?
      other_confidence_service = SecretScanning::AlertQueryService.for_repository(repository: current_repository, query: "is:open,closed confidence:other", current_user: T.must(current_user))
      other_confidence_result, service_error = other_confidence_service.get_filter_options(filter: SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER)

      if service_error
        return render plain: "Unable to load secret type options.", status: :internal_server_error
      end

      result = result + other_confidence_result
      query = "is:open"
    end

    index_payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(current_repository, T.must(current_user))
    filter_options = index_payload_builder.filter_provider_options_payload(query, result)
    respond_to do |format|
      format.json do
        render json: { options: filter_options }
      end
    end
  end

  sig { void }
  def locations # rubocop:todo GitHub/UseRestfulActions
    show_payload_builder = SecretScanning::Models::React::ShowPayloadBuilder.new(current_repository, T.must(current_user))
    current_page = params[:page].present? ? params[:page].to_i : 1
    result, error = alerts_service.get_alert(current_repository, T.must(current_user), params[:id].to_i, current_page)

    unless error.nil?
      log_service_error("Unable to fetch secret scanning alert", __method__.to_s, error, params[:id])

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
    if (T.must(token_scan_result)).on_demand_check_allowed?
      data = alerts_service.validate_token_on_demand(current_repository, T.must(current_user), params[:id].to_i)
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
  def check_user_has_view_permission
    # we bail out early if the user can access the scanning UI, typically as admins someone granted explicit access.
    return if self.token_scanning.view_alerts_allowed?(current_user)

    # we error out if anyone tries to access the index action otherwise, as thats not allowed.
    return render_404 if params[:action] == "index"

    # the code below focuses on making sure the user is a committer and can view any of the committer based endpoints.
    return render_404 unless ::SecretScanning::AccessControl::CommitAuthorView.new(current_repository).has_access_to_repository?(T.must(current_user))

    return render_404 unless token_scan_result&.scan_scope == :COMMIT

    # validate current_user is allowed to see this result
    # rubocop:todo GitHub/AvoidCast
    render_404 unless T.cast(current_repository, Repository).any_commits_authored_by_user?(current_user, T.must(token_scan_result).commit_oids)
    # rubocop:enable GitHub/AvoidCast
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
    return if token_scan_result.present? && self.token_scanning.resolve_alerts_allowed?(current_user, T.must(token_scan_result).commit_oids)

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

  sig { returns(SecretScanning::Services::AlertsService) }
  memoize def alerts_service
    SecretScanning::Services::AlertsService.new
  end

  sig { returns(T.nilable(GitHub::TokenScanning::Service::Token)) }
  memoize def token_scan_result
    result, error = self.alerts_service.get_alert(current_repository, T.must(current_user), params[:id].to_i, nil)

    unless error.nil?
      log_service_error("Unable to fetch secret scanning alert", __method__.to_s, error, params[:id])
      return nil
    end

    result
  end

  sig { params(payload: T::Hash[T.untyped, T.untyped]).returns(T.untyped) }
  def render_react_app_with_sidebar(payload)
    title = "Secret scanning · #{current_repository.name_with_display_owner}"
    unless payload[:query].nil?
      title += " (filters applied)" if payload[:query][:filters_applied]
    end

    other_conf_patterns_available = lower_confidence_patterns.feature_available? || generic_secrets.feature_available?
    parsed_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: params[:query], allow_confidence: other_conf_patterns_available)
    query_includes_other_confidence = parsed_query.confidence == Search::Queries::SecurityCenter::SecretScanningQuery::OTHER_CONFIDENCE

    layout = "layouts/secret_scanning/sidebar_container"
    if other_conf_patterns_available && query_includes_other_confidence
      layout = "layouts/secret_scanning/sidebar_container_other_confidence"
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
      ssr: true
    )
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
end
