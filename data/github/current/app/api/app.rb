# typed: true
# frozen_string_literal: true

require "graphql/client"
require "github/tagging_helper"
require "github/request_hmac_validator"
require "github/pi_link_collection"
require "forwardable"

# Core Sinatra controller for all API requests.
class Api::App < Sinatra::Base
  extend T::Sig

  include App::IController

  DefaultMediaTypes      = %w(application/json).freeze
  ParamsExcludedFromLogs = %w(captures splat).freeze
  AcceptedSortOrderings  = %w(asc desc).freeze
  VALID_ROUTE_OPTIONS = [
    :operation_id,
    :skip_rate_limit,
    :operation_ids,
    :exempt_from_tenant_context_requirement,
    :temporarily_exempt_from_tenant_context_requirement,
    :resolve_tenant_context,
  ].freeze

  DEFAULT_PER_PAGE = 30
  MAX_PER_PAGE     = 100

  include GitHub::ServiceMapping
  before do
    push_service_mapping_context
  end

  class << self
    attr_accessor :acceptable_media_types
  end

  extend Forwardable
  include Scientist
  include Platform::Authorization::RestApiFailedLoginHelper
  include Platform::Authorization
  include Api::App::UserLoginDependency
  include Api::App::EnterpriseInstallationDependency
  include Api::InstrumentSegment::SinatraHooks
  include Api::App::OpenApi

  # Wrap the method from `Platform::Authorization` with tracing for Lightstep
  def access_allowed?(verb, options = {})
    GitHub.tracer.in_span("access_allowed.#{verb}", kind: :internal) do |span|
      begin
        result = super
      ensure
        span.set_attribute("gh.auth.actor_is_authorized", result.nil? ? "false" : result.inspect)
      end
    end
  end

  # See GitHub::ServiceMapping#push_service_mapping_context
  # `HEAD` requests are treated like `GET` for service mapping
  def service_mapping_method
    env["github.api.route"]&.sub(/\AHEAD /, "GET ")
  end

  include RequestMethodHelper

  include Api::App::HmacDependency
  include Api::App::InputDependency
  include Api::App::DeliveryDependency
  include Api::App::FindersDependency
  include Api::App::RateLimitDependency
  include Api::App::ErrorDependency
  include Api::App::HelpersDependency
  include Api::App::RequestDependency
  include Api::App::FeatureFlagsDependency
  include Api::App::IpDependency
  include Api::App::PollIntervalDependency
  include Api::App::AuditDependency
  include Api::App::CursorPaginationDependency
  include Api::App::DeprecationDependency
  include Api::App::ApiVersionDependency
  include Api::App::TenantContextDependency
  include Api::App::HydroDependency
  include Api::App::RepositoriesDependency
  include Api::App::PaginationDependency
  include Api::App::LdapDependency
  include Api::App::NotificationsDependency
  include Api::App::GistsDependency
  include Api::App::GraphqlDependency
  include Api::App::ContentAuthorizationDependency

  disable :show_exceptions
  disable :protection

  # Installs the Executor. This allows the Sinatra API to use
  # any middleware installed with the Rails executor. As of 7.0 that's
  #   - ActiveRecord::QueryCache
  #   - ActiveRecord::AsynchronousQueriesTracker
  #
  # In a standard Rails application this would get installed by Railties
  # default middleware stack. But since this is a Sinatra API and we
  # want Rails Query Cache, this is required.
  use ActionDispatch::Executor, Rails.application.executor

  # Middleware for memoizing feature flags for the duration of a request to reduce latency of subsequent checks against the same flag.
  use FeatureFlag::Middleware::Memoizer

  use Api::Middleware::RouteFinder
  use Api::Middleware::RequestAuthenticationFingerprint
  use Api::Middleware::EnforceMediaType
  use Api::Middleware::Cors
  use Api::Middleware::Limiting,
      GitHub::Limiters::ByPath.new("/limittown"),
      Api::Limiters::AuthenticationFingerprintByPath.new(max: GitHub.authentication_fingerprint_by_path_max),
      Api::Limiters::EnterpriseSCIMByEndpoint.new(max: GitHub.enterprise_scim_by_endpoint_max),
      Api::Limiters::ElapsedTimeByAuthenticationFingerprint.new(max: GitHub.elapsed_time_by_authentication_fingerprint_max),
      Api::Limiters::ElapsedAuthenticatedTimeByPath.new("time-based-graphql", max: GitHub.elapsed_authenticated_time_by_path_graphql_max, path: "/graphql"),
      Api::Limiters::SearchIpAddress.new(max: GitHub.search_ip_address_max, ttl: GitHub.search_ip_address_ttl),
      Api::Limiters::ConcurrentAuthenticationFingerprint.new(
        max: GitHub.concurrent_authentication_fingerprint_max,
        ttl: GitHub.concurrent_authentication_fingerprint_ttl,
      ),
      Api::Limiters::GraphQLAuthenticationFingerprint.new(max: GitHub.graphql_authentication_fingerprint_max),
      Api::Limiters::TwirpAuthenticationFingerprintByPath.new(max: GitHub.twirp_authentication_fingerprint_by_path_max),
      Api::Limiters::TwirpElapsedTimeByClient.new(max: GitHub.twirp_elapsed_time_by_client_max),
      Api::Limiters::RequestsByPersonalAccessToken.new(max: GitHub.requests_by_pat_max)
  use Api::Middleware::Limiting::Disabled,
    Api::Limiters::GraphQLExcessiveDBCount.new(
      max: GitHub.graphql_excessive_db_count_max,
      threshold: GitHub.graphql_excessive_db_count_threshold,
      ttl: GitHub.graphql_excessive_db_count_ttl
    )
  use Api::Middleware::DatabaseSelection
  use PermissionCache

  # Enable load shedding based on queue times and deadline propagation based on
  # X-Client-Timeout-Ms if enabled in this deployment.
  use Api::Middleware::LoadShedding if ENV["LOAD_SHEDDING_ENABLED"] == "true" || Rails.env.test?

  unless Rails.env.production?
    use Api::Middleware::ProgrammaticAccessValidator, GitHub.programmatic_access_definitions
  end

  attr_reader :meta

  class PlatformExecute
    def self.execute(document:, operation_name: nil, variables: {}, context: {})
      target = context.delete(:target) || :internal
      Platform.execute(document, target: target, context: context, variables: variables, raise_exceptions: true).to_h
    end
  end

  PlatformClient = GraphQL::Client.new(
    schema: Platform::Schema,
    execute: PlatformExecute,
    enforce_collocated_callers: ENV["FASTDEV"] ? false : (Rails.env.development? || Rails.env.test?)
  )

  class TimeoutHandler
    def initialize(controller)
      @controller = controller
    end

    def timeout(_env)
      @controller.increment_rate_limit_and_set_headers!
    end
  end

  before do
    timeout_handler = TimeoutHandler.new(self)
    GitHub::TimeoutMiddleware.notify(env, timeout_handler)
    SecureHeaders.use_secure_headers_override(request, :api)
    @request_start_time = Time.now
    @original_time_zone = Time.zone
    @meta = {}
    @current_url = url_without_query(env)
    @links = PiLinkCollection.new @current_url, env["rack.request.query_hash"]
    @oauth = @current_repo = @pagination = nil

    infer_tenant_from_repo

    initialize_query_logs
    initialize_context
    initialize_log_data
    initialize_failbot
    initialize_ruby_crash_context
    initialize_sensitive_data
    initialize_audit_context
    populate_context_with_authentication_details
    populate_log_data_with_authentication_details
    populate_current_actor_hash_header
    check_allowlist_for_request_limiting
    initialize_trace_data

    @diff_custom_timeout_before = GitHub::Diff.custom_default_timeout
    GitHub::Diff.custom_default_timeout = GitRPC.timeout unless GitRPC.timeout.nil?

    ensure_acceptable_media_types!
    ensure_request_is_within_rate_limit!

    protect_access_to_garage_hosts
    protect_access_to_enterprise_hosts
    set_selected_api_version_for_request
  end

  before "/repositories/:repository_id/?*" do
    if path_includes_relocated_repo?
      redirect_to_new_repo_location_or_404! do |path, _requested_nwo, redirected_repo|
        path.sub %r(\A/repositories/\d+), "/repositories/#{redirected_repo.id}"
      end
    end

    if find_repo
      ensure_repo_is_accessible
      ensure_route_on_advisory_workspace_whitelist if current_repo&.advisory_workspace?
    end
  end

  def ensure_repo_is_accessible
    if current_repo_disabled_or_blocked?
      current_repo.disabled_access_reason # preload association prior to serialization

      deliver_blocked_repo_error!(current_repo) if current_repo.access.dmca?
      deliver_disabled_repo_error!(current_repo)
    end

    if !current_repo.active? || current_repo.hide_from_user?(current_user)
      deliver_error!(missing_repository_status_code, **missing_repository_options)
    end

    current_repo.network_broken?
  rescue Repository::NetworkDependency::NetworkMissingError => e
    Failbot.report e

    deliver_disabled_repo_error!(current_repo)
  end

  def ensure_route_on_advisory_workspace_whitelist
    deliver_error!(404) unless
      AdvisoryWorkspaceWhitelist.whitelisted?(current_repo, route_pattern, request.request_method)
  end

  def route_missing #rubocop:disable GitHub/ApiDeliverWrappersNamedDeliver
    deliver_error(404)
  end

  after "/(organizations|enterprises)/(:organization_id|:enterprise_id)/audit-log" do
    T.unsafe(self).update_audit_log_rate_limit_amount
  end

  after do
    GitHub::Diff.custom_default_timeout = @diff_custom_timeout_before
    Time.zone = @original_time_zone

    set_selected_api_version_response_headers
    increment_rate_limit_and_set_headers!

    record_stats
    finalize_log_data
    finalize_hydro_context
    instrument_api_request

    # This will validate the request/response
    # only when env["openapi.validation_enabled"] is true
    # which, for now, is only in the test environment.
    validate_openapi
  end

  # Helper methods to determine if the current request is being made by a robot,
  # and if so, which one.
  def robot?
    GitHub.robot?(request.user_agent.to_s)
  end

  # We disallow password auth to the API on dotcom now
  def password_auth_blocked?
    !GitHub.api_password_auth_supported?
  end

  # used to override `from` metric tag in app/platform/authorization.rb:api_auth() and
  # lib/github/authentication/attempt.rb:instrument()
  def source
    :api
  end

  # Internal
  #
  # Returns nothing.
  def initialize_query_logs
    ActiveSupport::ExecutionContext.set(controller: self)
  end

  # Internal: Populates Failbot with basic information about the current
  # request.
  #
  # Returns nothing.
  def initialize_failbot
    logging_repo = find_repo
    context = {
      "http.request.header.accept": env["HTTP_ACCEPT"],
      "http.route": route_pattern,
      "gh.db.connection_map": ApplicationRecord.connection_info,
      "code.namespace": self.class.to_s,
      "http.request.header.accept_language": env["HTTP_ACCEPT_LANGUAGE"],
      "process.parent_pid": Process.ppid,
      "gh.process.parent.started_at": GitHub.unicorn_master_start_time,
      "http.method": env["REQUEST_METHOD"],
      "gh.repo.is_private": logging_repo.try(:private?),
      "rails.version": Rails.version,
      "gh.repo.id": logging_repo.try(:id),
      "gh.request.category": request_category,
      "gh.request_id": env["HTTP_X_GITHUB_REQUEST_ID"],
      "gh.request.wait_duration": env[GitHub::TaggingHelper::REQ_WAIT_TIME],
      "gh.request.start_time": Time.now.utc,
      "service.instance.id": Rack::ServerId.get(env),
      "http.request.header.user_agent": env["HTTP_USER_AGENT"],
      "process.pid": Process.pid,
      "http.server.request.count": GitHub.unicorn_worker_request_count,
      "gh.process.started_at": GitHub.unicorn_worker_start_time,
      "gh.tenant.id": current_tenant&.id,
      "gh.actor.is_robot": robot?,
    }

    params_for_logging.each do |key, value|
      context["http.request.parameters.#{key}"] = value
    end

    ::Failbot.push(context)
  end

  # Internal: Populates extra crash info for cruby_crash_info
  # Returns nothing.
  def initialize_ruby_crash_context
    CRubyCrashInfo.info = <<~INFO
      request_id: #{env["HTTP_X_GITHUB_REQUEST_ID"]}
      method: #{request.request_method}
      path: #{request.fullpath}
      remote_ip: #{remote_ip}
      worker_pid: #{Process.pid}
      worker_request_count: #{GitHub.unicorn_worker_request_count}
      worker_started_at: #{GitHub.unicorn_worker_start_time}
    INFO
  end

  # Internal: Track sensitive data in this request.
  #
  # Returns nothing.
  def initialize_sensitive_data
    logging_repo = find_repo
    context = {
      # repo name is sensitive when it's private
      #
      # name_with_owner used only for logging therefore safe to user here.
      repo: logging_repo && logging_repo.private? ? logging_repo.name_with_owner : nil, # rubocop:disable GitHub/DoNotAllowNameWithOwner
      remote_ip: remote_ip,
    }

    SensitiveData.context.push(context)
  end

  # Internal: Populates GitHub.context with basic information about the current
  # request.
  #
  # Returns nothing.
  def initialize_context
    # WARNING: Do not call any methods that can cause the request to
    # short-circuit  (e.g., don't call any methods that attempt to authenticate
    # the request). Doing so will prevent us from fully populating the context.
    context = {
      actor_ip: remote_ip,
      user_agent: request.user_agent.to_s.dup.force_encoding(Encoding::UTF_8).scrub!,
      controller: self.class.to_s,
      from: "%s#%s" % [self.class, request.request_method],
      connections: ApplicationRecord.connection_info,
      referrer: Rack::RequestLogger.url_for_logging(request.env["HTTP_REFERER"]),
      request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
      request_method: request.env["REQUEST_METHOD"].downcase,
      request_category: request_category,
      api_route: route_pattern,
      server_id: Rack::ServerId.get(request.env),
      version: medias.to_api_semantic_version,
      tenant: current_tenant&.slug,
      is_robot: robot?,
    }

    # Leave this here instead of placing it in Rack::RequestLogger so that we
    # can keep the middleware lightweight.
    unless request.query_string.empty?
      context[:query_string] = query_string_for_logging
    end

    if defined?(GitHub.flipper) && GitHub.flipper[:rpc_mysql_dist_time_metric_extra_tags].enabled?
      controller = GitHub::TaggingHelper.controller(request.env)
      action = GitHub::TaggingHelper.action(request.env)
      method = GitHub::TaggingHelper.request_method(request.env)

      if controller && action && method
        GitHub.context.push(db_call_source_datadog_tags: [
          "source_type:request",
          "controller:#{controller}",
          "action:#{action}",
          "method:#{method}",
          "source:request-#{method}-#{controller}-#{action}",
        ])
      end
    end

    GitHub.context.push(context)
  end

  # Internal
  #
  # Returns nothing.
  def populate_context_with_authentication_details
    context = { auth: detect_auth }
    context[:current_user] = current_user&.to_s if logged_in?
    context[:oauth_application_id] = current_app.id if current_app
    context[:integration_id] = current_integration.id if current_integration

    if current_integration_installation
      context[:installation_id]   = current_integration_installation.id
      context[:installation_type] = current_integration_installation.ability_type
    end

    context[:parent_installation_id] = current_parent_integration_installation.id if current_parent_integration_installation
    # Forcing this read to a replica. The DatabaseSelection middleware is ignoring requests to /graphql, deferring
    # the selection to the GQL platform. This read here is inbetween and would always goes to the primary.
    ActiveRecord::Base.connected_to(role: :reading) do
      context[:enterprise_installation_id] = current_enterprise_installation.id if current_enterprise_installation
    end
    if logged_in?
      if current_user&.oauth_access
        scopes_string = current_user.oauth_access.scopes_string
        token_id = current_user.oauth_access.id

        context[:oauth_scopes] = scopes_string
        context[:oauth_access_id] = token_id
        context[:token_id] = token_id
        context[:token_scopes] = scopes_string
      elsif current_user&.programmatic_access
        token_id = current_user.programmatic_access.id

        context[:user_programmatic_access_id] = token_id
        context[:user_programmatic_access_name] = current_user.programmatic_access.name
        context[:token_id] = token_id
      end

    end

    # set actor_name in context if it is not nil
    actor_name&.tap { |name| context[:actor_name] = name }

    ::Failbot.push("gh.actor.id": current_user&.id)
    GitHub.context.push context
    # Audit log fields should not contain tenant suffixes in multi-tenant environments
    context[:current_user] = current_user&.display_login if logged_in?
    Audit.context.push context
  end

  # Internal: Adds a hash of the current_actor to the response headers
  def populate_current_actor_hash_header
    if current_actor && GitHub.flipper[:github_actor_id_header].enabled?
      headers["X-GitHub-Actor-Id"] = Digest::SHA256.hexdigest(current_actor.to_global_id.to_s)
    end
  end

  # Internal: A Hash of data to be logged that is stored in the request env.
  # This will eventually be logged by Rack::RequestLogger.
  #
  # Returns a Hash.
  def log_data
    env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= GitHub::Logger.empty
  end

  # Internal: Store basic information to be logged for the current request.
  #
  # Returns nothing.
  def initialize_log_data
    context = GitHub.context.to_hash

    # WARNING: Do not call any methods that can cause the request to
    # short-circuit  (e.g., don't call any methods that attempt to authenticate
    # the request). Doing so will prevent us from fully populating the logging
    # context.
    context_log_data = {
      "code.namespace": context[:controller],
      "http.path": context[:path_info],
      "http.query": context[:query_string],
      "gh.api.version": context[:version],
    }
    log_data.merge!(context_log_data)
  end

  # Internal: Store information to be logged about the authenticated actor.
  #
  # Returns nothing.
  def populate_log_data_with_authentication_details
    context = GitHub.context.to_hash

    log_data.merge!(
      "gh.auth.type": context[:auth],
      "gh.actor.id": current_user&.id,
      "gh.actor.login": current_user&.login_for_api,
      "gh.oauth.access.id": context[:oauth_access_id],
      "gh.oauth.app.id": context[:oauth_application_id],
      "enduser.scope": context[:oauth_scopes],
      "gh.integration.id": context[:integration_id],
      "gh.installation.id": context[:installation_id],
      "gh.installation.type": context[:installation_type],
      "gh.parent_installation.id": context[:parent_installation_id],
      "gh.user_programmatic_access.id": context[:user_programmatic_access_id],
      "gh.api.is_protected_by_hmac": is_protected_by_hmac?,
      "gh.user.is_employee": request_authorized_by_employee?,
    )

    actor = current_user&.login_for_api(use: :unique)
    log_data.merge!({
      "gh.actor.name": current_user&.login_for_api(use: :display),
      "user": actor,
      "gh.actor.login": actor,
    })

    log_data
  end

  # Internal: Add data only available at the end of the request to log_data.
  #
  # Returns nothing.
  def finalize_log_data
    log_ips
    log_route_pattern
    log_unconverted_path
    log_org_owned_resource_info
    log_rate_limit_info
    log_repo_info
    log_selected_version
  end

  # Mark request as whitelisted from request limiting by setting an env
  # variable if the request matches whitelist rules.
  def check_allowlist_for_request_limiting
    if logged_in? && current_user&.rate_limit_exempt_user?
      GitHub::Limiters::Middleware.skip_limit_checks(env)
    end
  end

  # Internal: Add API-specific data to the span that represents this request.
  #
  # Returns nothing.
  def initialize_trace_data
    if route_pattern
      GitHub.current_span&.name = "#{request.request_method} #{route_pattern}"
    end
    GitHub.current_span&.add_attributes({
      "code.namespace" => GitHub::TaggingHelper.controller(request.env),
      "http.route" => route_pattern,
      "gh.request.category" => GitHub::TaggingHelper.category(request.env),
      "rails.version" => GitHub::TaggingHelper.rails_version,
      "gh.session.is_logged_in" => GitHub::TaggingHelper.logged_in(request.env),
      "gh.actor.is_robot" => robot?,
      "gh.request.is_pjax" => GitHub::TaggingHelper.pjax(request.env),
      "http.accept" => request.accept.map(&:entry).join(",")
    }.reject { |_, v| v.nil? })
  end

  # Returns the elapsed time for the request in seconds
  def request_elapsed_time
    return nil if @request_start_time.blank?

    Time.now - @request_start_time
  end

  # Returns the elapsed time for the request in milliseconds
  def request_elapsed_time_in_ms
    if elapsed = request_elapsed_time
      elapsed * 1000
    end
  end

  def record_stats
    stats = {
      GitHub::TaggingHelper::VERSION_TAG => medias.api_semantic_versions,
      GitHub::TaggingHelper::AUTH_TAG => detect_auth,
      GitHub::TaggingHelper::CONTROLLER_TAG => GitHub::TaggingHelper.controller(env),
      GitHub::TaggingHelper::ROUTE_TAG => route_pattern,
      GitHub::TaggingHelper::METHOD_TAG => GitHub::TaggingHelper.request_method(env),
      GitHub::TaggingHelper::STATUS_TAG => response.status.to_i,
      GitHub::TaggingHelper::STATUS_RANGE_TAG => GitHub::TaggingHelper.status_range(response.status.to_i),
      GitHub::TaggingHelper::CATALOG_SERVICE_TAG => GitHub::TaggingHelper.catalog_service(env),
      :elapsed => request_elapsed_time_in_ms,
    }

    if @selected_api_version && !@selected_api_version.skipped?
      # dont use invalid user-provided values as tags for metrics since that can cause
      # an explosion of different tags and also trigger high costs
      requested_version_for_metrics = @selected_api_version.requested_version if @selected_api_version.reason != Api::SelectedVersion::REASON_INVALID

      stats.update({
        GitHub::TaggingHelper::REQUESTED_API_VERSION_TAG => requested_version_for_metrics,
        GitHub::TaggingHelper::SELECTED_API_VERSION_TAG => @selected_api_version.version,
        GitHub::TaggingHelper::SELECTED_API_VERSION_REASON_TAG => @selected_api_version.reason,
      })
    end

    GitHub::Stats::Api.record stats
  end

  # Returns the abstract URI pattern for the Sinatra route that is
  # processing the current request.
  #
  # The route pattern is not available until the route gets executed (e.g., it's
  # not available inside a Sinatra `before` block).
  #
  # This method requires https://github.com/sinatra/sinatra/pull/702 or a local
  # patch.
  #
  # env - Hash request environment.
  #
  # Examples
  #
  #   route_pattern
  #   => "/"
  #
  #   route_pattern
  #   => "/repositories/:repository_id/issues/:id"
  #
  # Returns a String, or nil if the route pattern has not yet been determined
  # for the request.
  def self.route_pattern(env)
    route = GitHub::TaggingHelper.api_route(env)
    GitHub::TaggingHelper.api_action(route)
  end

  def route_pattern
    self.class.route_pattern(env)
  end

  sig { params(methods: T.untyped, bk: T.proc.bind(T.attached_class).void).void }
  def self.verbs(*methods, &bk)
    opts = methods.last.is_a?(Hash) ? methods.pop : {}
    path = methods.pop
    conditions = @conditions
    methods.each do |method|
      @conditions = conditions.dup
      route(method.to_s.upcase, path, opts, &bk)
    end
  end

  def detect_auth
    return :anon if anonymous_request?
    # Some auth types are only relevent when a user is authenticated and some
    # are only valid when an application is authenticated (using their
    # application credentials)
    if logged_in?
      if current_user&.oauth_access
        return :integration if current_integration.present?
        return :personal_access_token if current_app.blank?
        return :oauth
      elsif current_user&.programmatic_access
        return :programmatic_access_token
      else
        return :integration_installation if current_integration_installation.present?
        return :basic if request_credentials.login_password_present?
        return :deploy_key if logged_in_as_key?
      end
    else
      return :oauth_key_secret if current_app.present?
    end
    :unclassified
  end

  error Repositories::Domain::BadActorGate::Error::UnprocessableEntity do
    deliver_error! 422,
      message: Repositories::Domain::BadActorGate::Error::UnprocessableEntity::MESSAGE,
      documentation_url: "/repositories/creating-and-managing-repositories/repository-limits#organization-limits"
  end

  error GitRPC::RepositoryOffline do
    failbot env, app: "github-unrouted"

    deliver_error! 503, message: "Repository offline"
  end

  error GitHub::DGit::NotFoundError do
    failbot env, app: "github-unrouted"

    deliver_error! 500, message: "Repository offline"
  end

  error GitRPC::InvalidRepository do
    Failbot.push app: "github-unrouted"
    Failbot.report env["sinatra.error"]

    message = "Unable to read Git repository contents. " \
              "We've notified our support staff. If this error " \
              "persists, or if you have any questions, please " \
              "contact us."

    deliver_error! 500,
      message: message,
      documentation_url: GitHub.contact_support_url
  end

  error GitRPC::BadObjectState do
    Failbot.report_user_error(env["sinatra.error"])

    deliver_error! 500,
      message: "There is a problem with this repository on disk. Please contact support for additional information or help."
  end

  error do
    error = env["sinatra.error"]
    failbot!(env)
    log_exception(error)
    # Return `nil` here so that Sinatra will apply the default `500` status code
    nil
  end

  # Log an exception to Failbot.
  #
  # env     - The Rack environment Hash.
  # options - The Hash of options to add to the Failbot payload (default: {}).
  #           :exception - The exception that will be provided to Failbot
  #                        (optional).
  #
  # Examples
  #
  #   # Gets the exception from the env['sinatra.error'] & reports it to Failbot
  #   failbot(env)
  #
  #   # Reports the given exception (+boom+) to Failbot
  #   failbot(env, :exception => boom)
  #
  # Returns nothing.
  def failbot(env, options = {})
    options_for_failbot = options.dup

    begin
      err = options_for_failbot.delete(:exception) || env["sinatra.error"]
      ::Failbot.report(err, options_for_failbot.update(
        "gh.exception.create_time": ((Time.now - @request_start_time) rescue "N/A"),
      ))
    rescue # rubocop:todo Lint/GenericRescue
      puts $!
    end
  end

  # Logs an exception to Failbot and delivers an error (HTTP 500) as the
  # API response.
  #
  # See +failbot+ for more details.
  #
  # Returns nothing.
  def failbot!(env, options = {})
    Failbot.push("gh.exception.is_critical": true)
    failbot(env, options)
    deliver_error 500
  end

  # Internal: Filters sensitive data (if any) from the URL, to provide a URL
  # that is suitable for logging.
  #
  # Examples
  #
  #   # GET https://api.github.com/users?client_id=abc&client_secret=def
  #   query_string_for_logging
  #   # => "https://api.github.com/users?client_id=abc&client_secret=-FILTERED-"
  #
  # Returns a String.
  def url_for_logging
    return request.url if request.query_string.empty?

    "#{GitHub.api_url}#{request.path}?#{query_string_for_logging}"
  end

  # Internal: Filters sensitive data (if any) from the query string, to provide
  # a query string that is suitable for logging.
  #
  # Examples
  #
  #   # GET /users?client_id=abc&client_secret=def
  #   query_string_for_logging
  #   # => "client_id=abc&client_secret=-FILTERED-"
  #
  # Returns a String, or nil if the request has no query string.
  def query_string_for_logging
    return nil if request.query_string.empty?

    url = request.url.gsub("%00".freeze, "-FILTERED-NUL-".freeze)
    uri = Addressable::URI.parse(url)
    unfiltered_query_values = uri.query_values || {}
    uri.query_values =
      filter_sensitive_params_for_logging(unfiltered_query_values)
    uri.query
  rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
    # This is unlikely to happen, since `request.url` was already accepted by the HTTP and application layers,
    # but if it does, don't raise this error since it might contain sensitive information.
    raise ArgumentError, "Failed to parse `request.url` for extracting the query string"
  end

  # Internal: Filters sensitive data (if any) from the request parameters, to
  # provide a parameter Hash that is suitable for logging. (The request
  # parameters include parameters provided via the query string and parameters
  # provided via the request body.)
  #
  # Returns a Hash.
  def params_for_logging
    without_noisy_params = reject_noisy_params_for_logging(params)

    filter_sensitive_params_for_logging(without_noisy_params)
  end

  def platform_execute(operation, variables: {}, target: :internal, force_readonly: false)
    PlatformClient.query(operation, context: platform_context.merge(target: target, force_readonly: force_readonly, track_query_name: true), variables: variables)
  end

  def platform_context
    {
      viewer:                        current_user,
      oauth_app:                     current_app,
      integration:                   current_integration,
      installation:                  current_integration_installation,
      actor:                         current_actor,
      feature_flags:                 request.env["HTTP_GRAPHQL_FEATURES"].to_s.split(",").map(&:to_sym),
      global_id_selection:           global_id_selection,
      granted_oauth_scopes:          current_user.try(:oauth_access).try(:scopes),
      origin:                        :rest_api,
      request_token:                 request_credentials.token,
      response:                      response,
      rate_limit_configuration:      rate_limit_configuration,
      user_agent:                    request.env["HTTP_USER_AGENT"],
      internal_ip_request:           internal_ip_request?,
      base_ip_request:               base_ip_request?,
      real_ip:                       request.env["HTTP_X_REAL_IP"],
      request_hmac:                  request.env["HTTP_REQUEST_HMAC"],
      request_client_ip:             request.env["HTTP_X_CLIENT_IP"],
      forwarded_for:                 request.env["HTTP_X_FORWARDED_FOR"],
      ip:                            request.ip,
      unauthorized_organization_ids: cap_filter.unauthorized_resource_ids(current_user_resources_for_cap_filter),
      cap_filter: cap_filter,
      cap_exclude_policies: [],
      serialize_login: serialize_login_selection,
      request_access_security_header: request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
      is_mirrored_request: Api::TrafficMirroring.mirrored_request?(request), # Traffic mirroring
    }
  end

  # Internal
  def current_user_resources_for_cap_filter
    ActiveRecord::Base.connected_to(role: :reading) do
      current_user&.resources_for_cap_filter
    end
  end

  # Internal: Allow internal services to define how login/NWO is serialized, whether to render unique or display
  # values according to their needs, per request, using the `X-Serialize-Login` header.
  def serialize_login_selection
    return :default unless GitHub.multi_tenant_enterprise?
    return :default unless GitHub.proxima_internal_api_unique_logins_required?
    case request.env["HTTP_X_SERIALIZE_LOGIN"]
    when "unique"
      :unique
    when "display"
      :display
    else
      :default
    end
  end

  # Internal
  def global_id_selection
    {
      user_preference: request.env["HTTP_X_GITHUB_NEXT_GLOBAL_ID"] == "1",
      user_opt_out: request.env["HTTP_X_GITHUB_LEGACY_GLOBAL_ID"] == "1",
    }
  end

  # Internal
  def reject_noisy_params_for_logging(params)
    params.reject { |k, _| ParamsExcludedFromLogs.include?(k) }
  end

  # Internal
  def filter_sensitive_params_for_logging(params)
    sensitive_params_filter.filter(params)
  end

  def sensitive_params_filter
    @sensitive_params_filter ||= GitHub::ParameterFilter.create
  end

  # Indicates if the request has requested pagination (regardless of if the method supports
  # or requires pagination).
  def wants_pagination?
    params[:page] || params[:per_page]
  end

  # Public: Paginator deals with pagination logic.
  #
  # Returns the cached Rest::Paginator or initializes a new one with the class default values
  def paginator
    return @paginator if @paginator
    @paginator = build_paginator
  end

  # Public: Initialize and cache a new paginator object.
  #
  # Returns the newly initialized paginator
  def build_paginator(default_per_page: self.class.const_get(:DEFAULT_PER_PAGE), max_per_page: self.class.const_get(:MAX_PER_PAGE))
    options = {
      page: params[:page],
      per_page: params[:per_page],
      default_per_page: default_per_page,
      max_per_page: max_per_page,
    }
    Rest::Paginator.new(**options)
  end

  def_delegators :paginator, :per_page, :default_per_page, :max_per_page

  def current_page
    paginator.page
  end

  # Public: Pagination parameters to pass to pagination methods.
  #
  # per_page - Integer number of records to fetch.
  # page     - The Integer page of records to fetch.
  #
  # Returns a Hash.
  def pagination
    @pagination = {
      per_page: paginator.per_page,
      page: paginator.page,
    }

    @pagination.update total_entries: pagination_capped_to_n_entries if pagination_capped_to_n_entries

    if (paginator.per_page * paginator.page) > WillPaginate::PageNumber::BIGINT
      deliver_error!(422, \
        message: "Pagination exceeds maximum limit of #{WillPaginate::PageNumber::BIGINT}", \
        documentation_url: "/rest/guides/using-pagination-in-the-rest-api")
    end

    @pagination
  end

  def paginate_rel(rel, pagination_opts = nil, skip_total_entries_count: false)
    pagination_opts ||= pagination

    if rel.respond_to?(:limit)
      paginated_rel = rel.limit(pagination_opts[:per_page]).page(pagination_opts[:page])
      if pagination_opts[:total_entries] && !skip_total_entries_count
        # We also need to unscope any set order here to avoid accidentally selecting the wrong
        # index, which could result in a slow query. As we're just interested in a count, the order
        # of results is irrelevant here.
        #
        # Also, the count is performed using a subquery to ensure that queries that make use of
        # `GROUP BY` and `HAVING` return the correct count.
        capped_count = rel.unscoped.from(
          rel.unscope(:order, :select).select("1 as one").limit(pagination_opts[:total_entries]),
        ).count
        paginated_rel.total_entries = capped_count
      end
      paginated_rel
    elsif rel.respond_to?(:paginate)
      rel.paginate(page: pagination_opts[:page], per_page: pagination_opts[:per_page])
    else
      WillPaginate::Collection.create(pagination_opts[:page], pagination_opts[:per_page],
                                      rel.length) do |pager|
        # cast nil, or, say, `Google::Protobuf::RepeatedField` types into `Array`
        pager.replace(Array(rel)[pager.offset, pager.per_page])
      end
    end
  end

  DEFAULT_PAGINATION_CAP = 40_000

  # Public: Declare the maximum number of entries returned by a method.
  #
  # entries - Integer number of entries.
  #
  # Halts with 422 if current pagination exceeds this limit.
  def cap_paginated_entries!(count = DEFAULT_PAGINATION_CAP)
    @pagination_capped_to_n_entries = count

    deliver_pagination_cap_exceeded! if count < (current_page * per_page)
  end

  # Internal: The maximum number of entries returned by the current
  # resource listing.
  #
  # Returns an Integer if the resource is capped, otherwise nil.
  def pagination_capped_to_n_entries
    @pagination_capped_to_n_entries
  end

  def protect_access_to_garage_hosts
    return unless GitHub.garage_unicorn?

    # If the request is going to be verified by HMAC signature then we don't need to worry about employee-based
    # verification.
    return if is_protected_by_hmac?

    unless request_authorized_by_employee?
      deliver_error! 401, message: "Must authenticate to access this API."
    end

    set_staff_only_cookie!
  end

  # Is the authenticated user GitHub staff or does it contain a signed proof
  # that a GitHub employee authorized the request?
  def request_authorized_by_employee?
    (
      current_user&.employee? ||
      GitHub::StaffOnlyCookie.read(request.cookies)
    )
  end

  # Is the request protected by HMAC signature verification?
  def is_protected_by_hmac?
    self.is_a?(Api::Internal) && require_request_hmac?
  end

  # Set the cookie for staff so `curl -c jar.txt` & `curl -b jar.txt` can be used
  # to make calls when not logged in to a staff user account. Curl docs: https://curl.se/docs/http-cookies.html
  def set_staff_only_cookie!
    return unless logged_in? && GitHub::StaffOnlyCookie.allowed_user?(current_user)
    # Note: We're in senatra so can't use the logic in `StaffOnlyCookie` to set the cookie for us
    if cookie = GitHub::StaffOnlyCookie.generate(user: current_user, for_lab: false)
      response.set_cookie(:staffonly, value: cookie.cookie_value, domain: ".#{GitHub.host_name}")
    end
  end

  def protect_access_to_enterprise_hosts
    return unless GitHub.private_mode_enabled?
    return if GitHub.proxima_internal_api_private_mode_bypass_enabled? && GitHub::Routers::Api.internal_api_host?(request.host)

    return if request.path_info == "/meta"
    return if request.path_info =~ /\A\/app-manifests\/[0-9a-f]+\/conversions\z/

    # Allow GitHub Connect's initial request that uses a license file as "authentication" in order
    # to obtain a temporary auth token. This is used to bootstrap the GitHub Connect installation,
    # is unique to GitHub Connect and is tantamount to an internal API request. This is only needed for Proxima.
    return if request.path_info == "/enterprise-installation" && request.request_method == "POST"

    return if trusted_port? || authenticated_for_private_mode?

    deliver_error! 401, message: "Must authenticate to access this API."
  end

  # Public: Determines whether the request is sufficiently authenticated to
  # access the API when running in Private Mode.
  #
  # For the vast majority of the API, being "authenticated" for Private Mode
  # means that you are authenticated as a *user*. So, in the default
  # implementation of this method, we consider the request to be authenticated
  # if it is authenticated as a user. For endpoints that allow other entities to
  # authenticate (e.g., OAuth Applications using client ID and secret), those
  # endpoints can override this method as appropriate to fit their definition of
  # "authenticated."
  #
  # See also: GitHub.private_mode_enabled?.
  #
  # Returns true if the request is authenticated; false otherwise.
  def authenticated_for_private_mode?
    return false unless logged_in?

    if GitHub.multi_tenant_enterprise? && current_user.bot? && GitHub.flipper[:proxima_bot_auth_target_tenant_enforcement].enabled?
      # check installation target tenant
      target = current_user&.installation&.target
      tenant_id = target.present? && target.instance_of?(Business) ? target.id : target&.business_id
      return false unless tenant_id.present?
      tenant = Business.find_by(id: tenant_id)
      return false unless tenant.present?
      # ensure the installation target tenant matches the currently requested tenant
      return GitHub::CurrentTenant.get == tenant
    end

    true
  end

  # Internal: For a request to any route that includes the repository
  # name-with-owner in the path (e.g., `/repos/:user/:repo`,
  # `/teams/:id/repos/:user/:repo`), return the repository name-with-owner.
  #
  # Returns a String or nil.
  def repo_nwo_from_path
    return @_repo_nwo_from_path if defined?(@_repo_nwo_from_path)
    @_repo_nwo_from_path = find_repo_nwo_from_router || find_repo_nwo_from_path
  end

  # Internal: For a request that matches `/repos/:user/:repo/*`, return the
  # repository name-with-owner.
  #
  # Returns a String or nil.
  def find_repo_nwo_from_router
    # GitHub::Routers::Api takes any request to `/repos/:user/:repo/*` and
    # re-routes it to `/repositories/:id/*`. When doing so, GitHub::Routers::Api
    # also preserves the originally-requested repository name-with-owner in an
    # environment variable.
    env[GitHub::Routers::Api::ThisRepositoryNameWithOwnerKey]
  end

  # Internal: For a request to any route that includes the `:user` and `:repo`
  # as named path segments (e.g., `/teams/:id/repos/:user/:repo`), return the
  # repository name-with-owner.
  sig { returns(T.nilable(String)) }
  def find_repo_nwo_from_path
    nwo = "#{params[:user] || params[:owner]}/#{params[:repo]}"

    return nwo if nwo =~ Repository::NAME_WITH_OWNER_PATTERN
  end

  # Internal: Is this request attempting to access a repository that has moved
  # to a new location (e.g., a renamed repository, a transferred repository)?
  sig { returns(T::Boolean) }
  def path_includes_relocated_repo?
    find_redirected_repo_from_path.present?
  end

  # Internal: If this request is attempting to access a repository that has
  # moved to a new location, find the relocated repository.
  sig { returns(T.nilable(Repository)) }
  def find_redirected_repo_from_path
    # We can't look up a redirect without a nwo from the path.
    return unless repo_nwo_from_path

    # If we have already found the repo, then no redirect is needed and we don't
    # need to bother looking up the repo or any redirects.
    return if env[GitHub::Routers::Api::ThisRepositoryKey]

    # If a repo exists for the requested name-with-owner, then don't check for
    # a redirect. This is a last chance backup check just in case the repo was not
    # previously looked up during routing for some reason. If we could trust the
    # router to _always_ properly set the repo we could drop this query too.
    return if Repository.nwo(repo_nwo_from_path)

    RepositoryRedirect.find_redirected_repository(repo_nwo_from_path)
  end

  # Internal: Redirect the request to the repository's new location.
  #
  # block - A block that returns the path to use for the redirect. The block
  #         receives the following arguments to assist in constructing the
  #         redirect path:
  #         :path            - A String representing the full path for this
  #                            request.
  #         :requested_nwo   - A String representing the repository
  #                            name-with-owner that this request is attempting
  #                            to access.
  #         :redirected_repo - The relocated Repository (that previously existed
  #                            at the requested name-with-owner location).
  #
  # Halts with a redirect if the requested repository has relocated (e.g., if it
  #   has been renamed, if it has been transferred, etc.).
  # Halts with a 404 if the request lacks permission to access the relocated
  #   repository.
  # Returns nothing.
  sig { params(block: T.proc.params(path: String, requested_nwo: String, redirected_repo: Repository).returns(String)).void }
  def redirect_to_new_repo_location_or_404!(&block)
    redirected_repo = find_redirected_repo_from_path

    env[GitHub::Routers::Api::ThisRepositoryKey] = redirected_repo

    if access_allowed?(:follow_repo_redirect, resource: redirected_repo, allow_integrations: true, allow_user_via_granular_actor: true)
      redirect_path =
        block.call(request.fullpath, repo_nwo_from_path, T.must(redirected_repo))

      deliver_redirect! \
        api_url(redirect_path), status: permanent_redirect_status_code
    else
      deliver_error!(missing_repository_status_code, **missing_repository_options)
    end
  end

  # Internal: The default status code to use if the repository for the current
  # request does not exist, or the user has no access to it.
  sig { returns(Integer) }
  def missing_repository_status_code
    404
  end

  # Internal: The default options to use if the repository for the current
  # request does not exist, or the user has no access to it.
  sig { returns(Hash) }
  def missing_repository_options
    {}
  end

  # Internal: The default status code to use if responding to this request with
  # a permanent redirect.
  #
  # For HEAD and GET requests, use a "301 Moved Permanently". When an HTTP
  # client follows the redirect, it will reuse the original HTTP verb.
  #
  # For other HTTP verbs, use a "307 Temporary Redirect". (If we used a 301,
  # most HTTP clients would change the HTTP verb to GET when following the
  # redirect.)
  sig { returns(Integer) }
  def permanent_redirect_status_code
    (request.get? || request.head?) ? 301 : 307
  end

  # Sets one or more custom media types that API Apps may accept.
  #
  # *types - One or more String media types.
  #
  # Returns nothing.
  def self.allow_media(*types)
    (self.acceptable_media_types ||= []).push(*types)
  end

  # Public: Get the GitHub-accepted media types from the request's accepted
  # media types.
  #
  # The API accepts "application/json" or any "application/vnd.github*" type.
  sig { returns(Api::AcceptedMediaTypes) }
  def medias
    @medias ||= Api::AcceptedMediaTypes.new(request.accept, request.env["PATH_INFO"])
  end

  def allow_media(*types)
    (@acceptable_media_types ||= []).push(*types)
  end

  def acceptable_media_types
    acceptable_types = Array(self.class.acceptable_media_types)

    if @acceptable_media_types
      acceptable_types.unshift(*@acceptable_media_types)
    end

    acceptable_types
  end

  # Checks to see if the current request's acceptable media types are valid.
  # Typically we only care about JSON, but some API classes might want to
  # support other types (like Atom).
  #
  # Returns true if the API response is not acceptable to the client, or false.
  def unacceptable_media_types?
    unless medias.acceptable?
      types = DefaultMediaTypes.dup
      types.push(*acceptable_media_types)
      !request.preferred_type(*types)
    end
  end

  # Public: Gets the preview headers passed as part of the request
  #
  # Returns an array of symbols.
  def schema_previews
    medias.api_semantic_versions
  end

  # Public: Gets the user agent for the request.
  #
  # Returns an Api::UserAgent.
  sig { returns(Api::UserAgent) }
  def user_agent
    @user_agent ||= Api::UserAgent.new(request.user_agent)
  end

  # Public: Gets the port the request is coming in on. This is so we
  # can limit particular API namespaces to only work for requests
  # coming in on trusted ports.
  #
  # Returns a String port.
  def server_port
    env["SERVER_PORT"]
  end

  # Public: Determines whether the port the request is coming in on
  # is a trusted port.
  sig { returns(T::Boolean) }
  def trusted_port?
    GitHub.trusted_ports_enabled? && GitHub.trusted_ports.include?(server_port) && GitHub.trusted_ips.include?(remote_ip)
  end

  # Public: Determines originating IP address.
  def remote_ip
    env["api.remote_ip"] ||= request.ip
  end

  def request_reflog_data(via)
    # name_with_owner and login are not used in the response therefore safe to use here.
    {
      real_ip: remote_ip,
      repo_name: current_repo.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
      repo_public: current_repo.public?,
      user_login: current_user.login, # rubocop:disable GitHub/DoNotAllowLogin
      user_agent: request.user_agent,
      from: GitHub.context[:from],
      via: via,
    }
  end

  # Internal: Log exception.
  #
  # exception - The Exception object to log.
  # data      - A Hash of key/value pairs to log in addition to the standard
  #             logging data (default: {}).
  #
  # Returns nothing.
  def log_exception(e, data = {})
    log_exception_to_stdout(e) if Rails.env.test?

    context_hash = GitHub.context.to_hash
    exception_logging_context = {
      "gh.request_id" => context_hash[:request_id],
      "gh.server_id" => context_hash[:server_id],
    }

    GitHub.logger.error(e, exception_logging_context)
  end

  # Internal: Log exception to STDOUT.
  #
  # exception - The Exception object to log.
  #
  # Returns nothing.
  def log_exception_to_stdout(exception)
    puts exception.message
    pp exception.backtrace
  end

  # Internal: Instrument an API call failing because of content authorization
  # errors.
  #
  # error - The ContentAuthorizationError instance
  #
  # Returns nothing.
  def instrument_content_authorization_failure(error:)
    GitHub.dogstats.increment "error.content_authorization", tags: ["via:api", "error:#{error.name}", "route:#{graph_friendly_route_key}"]

    log_data[:"gh.auth.failure.name"] = error.name
  end

  # Internal: Adds current route pattern to log context.
  #
  # Returns nothing.
  def log_route_pattern
    log_data[:"http.route"] = route_pattern
  end

  def log_ips
    log_data[:"http.request.header.x_real_ip"] = request.env["HTTP_X_REAL_IP"]
    log_data[:"http.request.header.x_forwarded_for"] = request.env["HTTP_X_FORWARDED_FOR"]
    log_data[:"http.request.header.x_client_ip"] = request.env["HTTP_X_CLIENT_IP"]
  end

  # Internal: Adds org and OAuth-related details to log context for org-owned
  # resources.
  #
  # Returns nothing.
  def log_org_owned_resource_info
    if org = current_resource_org_or_biz_owner
      log_data[:"gh.organization.id"] = org.id
      log_data[:"gh.organization.login"] = org.to_s
      if logged_in? && current_user&.using_oauth?
        oauth_party = if current_app.nil?
          "personal"
        elsif current_app.owned_by?(org)
          "first"
        else
          "third"
        end
        log_data[:"gh.oauth.app.party_type"] = oauth_party
      end
    end
  end

  # Internal: Logs if path was converted to ids from natural keys
  def log_unconverted_path
    unconverted = env[GitHub::Routers::Api::UnconvertedPathKey] ? true : false
    log_data[:"gh.api.is_unconverted_path"] = unconverted if unconverted
  end

  # Internal: Adds current rate limit info to log context.
  #
  # Returns nothing.
  def log_rate_limit_info
    if @rate
      @rate.update_logs(log_data)
    end
  end

  # Internal: Adds name and visibility for current repo (if any) to log
  # context.
  #
  # Returns nothing.
  def log_repo_info
    if repo = find_repo
      # name_with_owner used only for logging therefore safe to use here.
      repo_visibility = ActiveRecord::Base.connected_to(role: :reading) { repo.visibility }
      log_data.update({
        "gh.repo.name_with_owner" => repo.name_with_owner, # rubocop:disable GitHub/DoNotAllowNameWithOwner
        "gh.repo.visibility" => repo_visibility,
        "gh.repo.id" => repo.id,
      })
    end
  end

  def log_selected_version
    if @selected_api_version && !@selected_api_version.skipped?
      log_data.update({
        "gh.api.requested_version": @selected_api_version.requested_version,
        "gh.api.selected_version": @selected_api_version.version,
        "gh.api.selected_version_reason": @selected_api_version.reason
      })
    end
  end

  # for mysql hints.
  # see config/initializers/query_log_tags.rb
  def query_logs_route
    @query_logs_route ||= "%s#%s" %
      [self.class.name&.underscore, request.request_method.downcase]
  end

  # Human-readable route descriptor for use in tracking.
  #
  # Returns a String, e.g. "POST_repositories_REPOSITORY_ID_commits_SPLAT_comments"
  def graph_friendly_route_key
    @graph_friendly_route_key ||= begin
      [request.request_method,
       route_pattern.gsub(/\/:([\w_]+)\/?/) { |id| id.upcase }.
                     gsub("/", "_").
                     gsub("*", "SPLAT").
                     gsub(%r{[^a-zA-Z0-9_]}, "")].join
    end
  end

  def request_category
    REQUEST_CATEGORY
  end

  # no need to rebuild this string for _every_ AR query
  REQUEST_CATEGORY = "api".freeze

  # Helper for returning a proper API URL for the given relative path.
  #
  # path - Relative API path as String
  #
  # Examples:
  #
  #   Dotcom:
  #
  #   api_url("/foo/bar/baz")
  #   => "https://api.github.com/foo/bar/baz"
  #
  #   Enterprise:
  #
  #   api_url("/foo/bar/baz")
  #   => "https://ghe.io/api/v3/foo/bar/baz"
  #
  # Returns a String URL
  def api_url(path)
    Api::Serializer.url(path)
  end

  # Private: Build a web UI URL with the given path.
  #
  # path    - The path of the URL to build.
  # options - Query parameters to include in the URL.
  #           :auth - Whether to inclue a SignedAuthToken for the feed
  #                   (Default false).
  #
  # Returns a String URL.
  def html_url(path, options = {})
    if (_auth = options.delete(:auth))
      options[:token] = feed_token(path)
    end
    Api::Serializer.html_url path, options
  end

  # Private: Get a SignedAuthToken for an Atom feed with a given path.
  #
  # path - The path of the Atom feed the SignedAuthToken is for.
  #
  # Returns a String SignedAuthToken or nil if no user is logged in.
  def feed_token(path)
    return unless logged_in?
    GitHub::Authentication::Feed.token current_user, path
  end

  # Get the timezone name if given in headers
  def timezone_name
    if header = request.env["HTTP_TIME_ZONE"] || request.env["HTTP_X_TIME_ZONE"] ||
                request.env["HTTP_TIMEZONE"]
      name = header.split(";").last if header =~ /[[:print:]]+/
    end
    name.to_s
  end

  UTC = ActiveSupport::TimeZone["UTC"]

  # Get the timezone based on current request and user context
  def timezone_for_request(user)
    zone = ActiveSupport::TimeZone[timezone_name]
    zone ||= user.time_zone if user
    zone || UTC
  end

  # Internal: Indicates if the current repo is unavailable due to being
  # disabled, blocked, or broken.
  #
  # Returns a Boolean.
  def current_repo_disabled_or_blocked?
    ActiveRecord::Base.connected_to(role: :reading) do
      current_repo.access.disabled? ||
      current_repo.network_broken? ||
      current_repo.disabled?(viewer: current_user)
    end
  end

  def last_write_timestamp_for_current_user
    return unless logged_in?
    last_operations = DatabaseSelector::LastOperations.from_request_creds(
      request_credentials,
    )
    Timestamp.from_time(last_operations.last_write_timestamp)
  end

  def graphql_mime_body_variables(options)
    variables = {
      includeBody: T.let(true, T::Boolean),
      includeBodyHTML: T.let(false, T::Boolean),
      includeBodyText: T.let(false, T::Boolean),
    }

    if options[:mime_params].include?(:full)
      variables[:includeBodyHTML] = true
      variables[:includeBodyText] = true
    end

    if options[:mime_params].include?(:html)
      variables[:includeBodyHTML] = true
      variables[:includeBody]     = false
    end

    if options[:mime_params].include?(:text)
      variables[:includeBodyText] = true
      variables[:includeBody]     = false
    end

    if options[:mime_params].include?(:raw)
      variables[:includeBody] = true
    end

    variables
  end

  # @return [Organization, User, nil]
  def request_owner
    if defined?(@request_owner)
      @request_owner
    else
      # app/api/applications.rb overrides #find_current_app to return an Integration,
      # handle that here
      if current_app.is_a?(Integration) && current_integration.nil?
        req_integration = current_app
        req_oauth_app = nil
      else
        req_integration = current_integration
        req_oauth_app = current_app
      end

      @request_owner = Api::RequestOwner.call(
        # These inputs might be `nil`, `RequestOwner` will handle it:
        user: current_user,
        installation: current_integration_installation,
        integration: req_integration,
        oauth_application: req_oauth_app,
      )
    end
  end

  # determines the name of the current Integration, OAuth App or PAT
  def actor_name
    return current_app.name if current_app
    return current_integration.name if current_integration
    return current_user.programmatic_access.name if current_user&.programmatic_access
    return current_user.oauth_access.description if current_user&.oauth_access

    nil
  end

  # Adds a route. This method is called by `Sinatra::Base.get`, etc, and is not used directly.
  #
  # @param verb [String] the HTTP method/verb (all uppercase)
  # @param path [String] the path (with parameters)
  # @option options [Hash]
  # @param original_block [Proc] The handler for this endpoint
  # @return [void]
  sig { params(verb: T.untyped, path: T.untyped, options: T.untyped, original_block: T.proc.bind(T.attached_class).void).void }
  def self.route(verb, path, options = {}, &original_block)
    if !(options[:operation_id] || options[:operation_ids]) && !is_test_app?
      raise ArgumentError, "operation_id: or operation_ids: is required for #{verb} #{path}"
    end

    if options.key?(:operation_id)
      original_block = route_with_operation_id(verb, path, options, &original_block)
    end

    if options.key?(:operation_ids)
      original_block = route_with_operation_ids(verb, path, options, &original_block)
    end

    if options[:skip_rate_limit]
      # This is to match how sinatra builds `env["sinatra.route"]`
      # https://github.com/sinatra/sinatra/blob/2e980f3534b680fbd79d7ec39552b4afb7675d6c/lib/sinatra/base.rb#L1020
      path_s = Mustermann.new(path).to_s
      Api::App.skipped_rate_limit_paths << path_s
    end

    if options.key?(:exempt_from_tenant_context_requirement) && options.key?(:temporarily_exempt_from_tenant_context_requirement)
      raise ArgumentError, "Cannot use both :exempt_from_tenant_context_requirement and :temporarily_exempt_from_tenant_context_requirement"
    end

    exempt_from_tenant_context_requirement = options.key?(:exempt_from_tenant_context_requirement) || options.key?(:temporarily_exempt_from_tenant_context_requirement)
    if options.key?(:resolve_tenant_context) && exempt_from_tenant_context_requirement
      raise ArgumentError, "Cannot be exempt from tenant context requirement and define resolve_tenant_context. Api path, #{verb} #{path}."
    end

    original_block = if options.key?(:resolve_tenant_context)
      handle_tenant_context_requirement(verb, path, options, &original_block)
    elsif options[:exempt_from_tenant_context_requirement]
      route_unscoped(verb, path, &original_block)
    elsif options.key?(:temporarily_exempt_from_tenant_context_requirement)
      until_date = options[:temporarily_exempt_from_tenant_context_requirement]
      route_unscoped_until(verb, path, until_date, &original_block)
    else
      route_with_tenant_context_metrics(verb, path, &original_block)
    end

    # Unhandled options would trigger a `NoMethodError` from
    # `Sinatra::Base.compile!`, so we raise a better exception instead.
    # Do not mutate options as Sinatra may call this method with the same
    # hash more than once
    sinatra_options = options.reject { |k, _| VALID_ROUTE_OPTIONS.include?(k) }

    unless sinatra_options.empty?
      raise ArgumentError, "Unsupported options: #{sinatra_options.keys}"
    end

    super(verb, path, sinatra_options, &original_block)
  end

  sig { returns(T::Boolean) }
  def self.is_test_app?
    # Early return since there should never be test app defined or loaded in dev/production.
    return false if !Rails.env.test?

    # the name method can be nil for anonymous modules.
    !!T.must(name).match(/Test/)
  end
end
