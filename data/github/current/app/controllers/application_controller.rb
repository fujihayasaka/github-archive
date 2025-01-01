# typed: true
# frozen_string_literal: true

class ApplicationController < ActionController::Base
  abstract!

  NUMERIC_PAGE_PATTERN = /\A-?\d+/
  DEFAULT_PER_PAGE = 25      # Pagination
  # Maximum length of URL redirects before login flow. Varnish allows
  # headers up to 8k in length, this gives us enough headroom for a
  # safe `Location` header.
  MAX_URL_LOGIN_REDIRECT_LENGTH = 7680

  include GitHub::ServiceMapping
  # Set this as early as possible, before other modules are included
  # or before_action filters are run, to ensure we have set the
  # catalog_service for any DB queries that run
  before_action :push_service_mapping_context

  include PlatformHelper, UrlHelper, NewsiesControllerHelper,
    GitHub::Timer, ActionView::Helpers::AssetTagHelper,
    Mobile::ApplicationHelper

  include ApplicationController::RequestTimingDependency
  include ApplicationController::CodeNavDependency
  include ApplicationController::ErrorHandlingDependency
  include ApplicationController::PjaxDependency
  include ApplicationController::OriginTrialDependency
  include ApplicationController::TurboDependency
  include ApplicationController::RolesDependency
  include ApplicationController::EventsDependency
  include ApplicationController::EnterpriseDependency
  include ApplicationController::MultiTenantEnterpriseDependency
  include ApplicationController::ModelSettingsDependency
  include ApplicationController::RequestCategoryDependency
  include ApplicationController::GracefulTimeoutDependency
  include ApplicationController::AuthenticatedSystem
  include ApplicationController::UserSessionDependency
  include ApplicationController::SavedUserSessionsCookieDependency
  include ApplicationController::SudoDependency
  include ApplicationController::ConditionalAccessDependency
  include ApplicationController::ExternalSessionsDependency
  include ApplicationController::CookiesDependency
  include ApplicationController::SecurityHeadersDependency
  include ApplicationController::AuthenticityTokenDependency
  include ApplicationController::AnalyticsDependency
  include ApplicationController::EmailTrackingDependency
  include ApplicationController::StatsDependency
  include ApplicationController::DatabaseDependency
  include ApplicationController::JsonXhrRequirementDependency
  include ApplicationController::ControllerAssetsBundlerDependency
  include ApplicationController::TurboCacheControlDependency
  include ApplicationController::PaginationDependency
  include ApplicationController::HovercardDependency
  include ApplicationController::ProjectsDependency
  include ApplicationController::AuditDependency
  include ApplicationController::TradeControlsDependency
  include ApplicationController::TradeScreeningDependency
  include ApplicationController::NotificationsDependency
  include ApplicationController::VarnishDependency
  include ApplicationController::PreloadFeatureFlagsDependency
  include ApplicationController::LocalizationDependency
  include ApplicationController::ColorModeDependency
  include ApplicationController::PublicCodespacesDependency
  include ApplicationController::CanonicalRequestDependency
  include ApplicationController::AfterResponseDependency
  include ApplicationController::ClusterOwnershipDependency
  include ApplicationController::AccountTwoFactorRequirementDependency
  include ApplicationController::SyntheticTestDependency
  include ApplicationController::TwoFactorCheckupDependency
  include ApplicationController::DefaultRateLimitDependency
  include ApplicationController::CustomerCategoryDependency
  include ApplicationController::SkipMcDependency
  include ApplicationController::SearchIndexOverrideDependency
  include ApplicationController::ReturnToDependency
  include ApplicationController::CopilotDependency
  include ApplicationController::PersistedGraphqlQueryDependency

  include GitHub::Memoizer
  include GitHub::RateLimitedRequest

  if !Rails.env.production?
    prepend ApplicationController::SafetyCheckForRenderWhenRespondingTo
  end

  include GitHub::RouteHelpers
  include ViewModelHelper
  include FailbotHelper
  include GitHub::BrowserStatsHelper
  include Scientist
  include GlobalNavigationHelper
  include StaticAssetHelper

  # CSP Exceptions
  include PjaxContentPolicy
  include InsightsHelper
  before_action :add_insights_csp_exceptions

  # Application-wide filters
  #
  # Please be cautious when adding new app filters. They affect the behavior
  # and performance of every controller and action.
  #
  # No prepend_ filters allowed.
  #
  # PDI: All these filters could use an audit to see how necessary they are.
  # Or if they could simpily be invoked by manually. We should group and
  # document filters that are expected to throw exceptions and halt the filter
  # chain.

  if Rails.env.test?
    around_action :disable_optional_clusters
  end

  around_action :with_user_timezone
  before_action :setup_request_context
  before_action :initialize_log_data
  # This filter must execute before any others that query `preview_features?`
  before_action :set_site_admin_and_employee_status

  # Filters to set global response headers, cookies, and categorize requests.
  # Most other general filters, especially those that may render an HTML
  # template, should not appear before this group.
  before_action :set_security_headers
  before_action :employee_only_unicorn
  before_action :set_employee_cookie, unless: :stateless_request?
  before_action :request_categorization_filter
  before_action :set_user_headers
  before_action :set_rails_version_header
  before_action :set_vary_pjax, :set_pjax_url, :set_vary_turbo, :set_vary_requested_with

  around_action :staff_platform_loader_tracker
  around_action :staff_rails_instrumentation
  around_action :staff_external_service_profiler
  around_action :staff_mysql_instrumentation, if: lambda {
    T.bind(self, ApplicationController)
    params[:mysql_query_trace]
  }
  around_action :staff_api_insights_instrumentation, if: lambda {
    T.bind(self, ApplicationController)
    params[:_tracing]
  }

  # After this point, it should be safe to render HTML from a filter.
  # Banner to alert user we will be enforcing 2FA for their account
  before_action :account_2fa_requirement_banner
  before_action :account_2fa_requirement_interrupt
  before_action :require_two_factor_checkup

  # Simulate an action that calls `current_visitor` for tests
  before_action :current_visitor, if: -> do
    T.bind(self, ApplicationController)
    Rails.env.test? && params[:find_current_visitor]
  end

  if GitHub.enterprise?
    # See enterprise_dependency.rb
    before_action :enforce_private_mode
    before_action :license_invalid_check
    before_action :license_expiration_check
    before_action :first_run_check
    before_action :override_referrer_policy
  else
    before_action :track_emails
    before_action :enforce_multi_tenant_private_mode, if: :multi_tenant_enterprise?
  end

  protect_from_forgery(with: :exception, if: :verify_authenticity_token?)

  before_action :trace_web_request

  before_action :mandatory_message_check, if: -> { GitHub.enterprise? }

  before_action :touch_user_session

  include Site::CookieConsentDependency
  before_action :enable_cookie_consent

  include Site::FullstoryCaptureDependency
  helper_method :fullstory_enabled?

  # AbstractRepositoryController has 2 filters that it insists on running
  # before others. We can't use prepend_before_action anymore, so the order
  # is explicitly stated here but conditioned to only run for the
  # AbstractRepositoryController subclass.
  #
  # TODO: We should try to refactor these filters so they don't need to be ran
  # so early in the chain. Or maybe just removed entirely.
  before_action :ask_the_gatekeeper, :set_path_and_name,
    if: lambda { |c| c.is_a?(AbstractRepositoryController) }

  before_action :disable_session, if: :stateless_request?
  before_action :permission_denied_if_mismatched_login_and_token
  before_action :skip_mc_check
  before_action :enforce_oauth_scope
  before_action :cap_pagination
  # faulty linter - we're enabling CAP for all controllers here
  before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :initialize_hydro_context
  before_action :set_default_nav_breadcrumb
  before_action :cpq_check
  before_action :with_request_time_budget_control

  rate_limit_requests \
    if: :endpoint_rate_limited_by_default?,
    max: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_MAX,
    key: :default_rate_limit_key,
    ttl: GitHub::RateLimitedRequest::DEFAULT_RATE_LIMIT_TTL

  after_action :set_pjax_version
  after_action :set_login_cookie, unless: :stateless_request?
  after_action :sanitize_pjax_redirects
  after_action :block_non_xhr_json_responses
  after_action :set_color_mode_cookie

  def clear_weak_password_session_variable
    session.delete(::CompromisedPassword::WEAK_PASSWORD_KEY)
  end

  def request_time_left
    start_time = request.env["process.request_start"] || Process.clock_gettime(Process::CLOCK_MONOTONIC)
    GitHub.request_timeout(request.env) - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time)
  end
  helper_method :request_time_left

  def remote_ip
    request.remote_ip
  end

  # The Rack environment hash.
  def env
    request.env
  end

  # Public: A Hash of data to be logged that is stored in the request env.
  # This will eventually be logged by Rack::RequestLogger.
  #
  # Returns a Hash.
  def log_data
    request.env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= GitHub::Logger.empty
  end
  helper_method :log_data

  def read_fragment(key, options = nil)
    fragment = super
    if fragment && fragment.encoding == Encoding::ASCII_8BIT
      GitHub.dogstats.increment("fragment", tags: ["action:view", "type:binary"])

      fragment.force_encoding "UTF-8"
      unless fragment.valid_encoding?
        GitHub.dogstats.increment("fragment", tags: ["action:view", "type:binary", "error:invalid_bytes"])
        fragment.scrub!
      end
    end

    fragment
  end

  # SSH Key auditing enabled?
  #
  # Disable auditing if LDAP Sync is enabled and SSH Keys are managed by LDAP.
  def audit_ssh_enabled?
    return true if !GitHub.enterprise?
    !GitHub.auth.ssh_keys_managed_externally?
  end
  helper_method :audit_ssh_enabled?

  # Password resets can only be done for built-in users
  # (external users should reach their providers for that)
  def password_reset_enabled?
    !GitHub.auth.external_user?(current_user)
  end
  helper_method :password_reset_enabled?

  def response_code_for_rescue(exception)
    ActionDispatch::ExceptionWrapper.rescue_responses[exception.class.name]
  end

  def render_optional_error_file(status_code)
    set_static_file_csp
    status = Rack::Utils.status_code(status_code)
    path = "#{Rails.public_path}/#{status.to_s[0, 3]}.html"
    if !performed? && File.exist?(path)
      render file: path, status: status, layout: false, formats: [:html]
    else
      head status
    end
  end

  def blocked_by_author?(author)
    logged_in? && current_user.blocked_by?(author)
  end

  # The GitHub::ServiceMapping module expects this method in order to properly initialize the
  # service mapping for the request in push_service_mapping_context.
  def service_mapping_method
    action_name
  end

  # Always returns false (even if no repository exists for this request).
  # Overridden in RepositoryControllerMethods for Repository based controllers
  # and views.
  #
  # Returns false.
  def current_repository_locked_for_migration?
    false
  end
  helper_method :current_repository_locked_for_migration?

  # Always returns true (even if no repository exists for this request).
  # Overridden in RepositoryControllerMethods for Repository based controllers
  # and views.
  #
  # Returns true.
  def current_repository_writable?
    true
  end
  helper_method :current_repository_writable?

  # Public: Find or create a site visitor that is trackable by Octolytics. The
  # primary use case for interacting with the `current_visitor` is to perform
  # A/B testing.
  #
  # Visitor ids are persisted in the `_octo` cookie.
  #
  def current_visitor
    @current_visitor ||= find_current_visitor || create_current_visitor
  end
  helper_method :current_visitor

  private

  helper_method :current_repository, :issue_path, :current_page

  def at_auth_limit?
    return @at_auth_limit if defined? @at_auth_limit

    @at_auth_limit = if GitHub.web_ip_lockouts_enabled?
      AuthenticationLimit.at_any?(web_ip: request.remote_ip)
    end
  end
  helper_method :at_auth_limit?

  def at_auth_limit_login?
    # For dotcom, we cache GET and HEAD responses in varnish, so
    # we shouldn't use remote_ip to decide anything about how to
    # handle the request.
    return false if request.get? || request.head?
    at_auth_limit?
  end
  helper_method :at_auth_limit_login?

  class InvalidParameterError < ArgumentError; end

  def current_page(page_param = :page)
    if params[page_param].blank? || !params[page_param].respond_to?(:to_i)
      1
    else
      params[page_param].to_i.abs
    end
  end

  def current_repository
    nil
  end

  # This is overridden by ApplicationController::VerifiedFetchDependency which is only included on a subset of controllers.
  # This stub allows us to reliably call this on every controller in ApplicationController::StatsDependency#report_api_insights_information
  def use_verified_fetch?
    false
  end

  def log_login(sign_in_verification_method, authentication_record, passwordless_credential)
    payload = {
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
      user_session_id: user_session.id,
    }

    if current_user.sign_in_analysis_enabled?
      payload[:sign_in_verification_method] = sign_in_verification_method
    end

    if !passwordless_credential.nil?
      payload[:passkey_id] = passwordless_credential.id
      payload[:passkey_nickname] = passwordless_credential.nickname
    end

    current_user.instrument_login(payload) if current_user.is_a?(User)

    GlobalInstrumenter.instrument "user.successful_login", {
      actor: current_user,
      primary_email: current_user.primary_user_email,
      elected_to_receive_marketing_email: NewsletterPreference.marketing?(user: current_user),
      return_to: session[:return_to],
      authentication_record: authentication_record,
      passwordless: !passwordless_credential.nil?,
    }
  end

  def log_switch_accounts(from_session, to_session)
    GlobalInstrumenter.instrument "user.switch_accounts", {
      actor: current_user,
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
      from_user_session_id: from_session.id,
      to_user_session_id: to_session.id,
      return_to: session[:return_to],
    }
  end

  def update_login_metadata
    if logged_in? && current_user.is_a?(User)
      current_user.save_login_metadata(ip: request.remote_ip)
    end
  end

  def redirect_to(*args)
    if sudo_redirect_to_back?(args)
      safe_redirect_to(params[:sudo_referrer], allow_hosts: [GitHub.host_name, GitHub.admin_host_name])
    elsif args.first == :back
      without_back = args - [:back]
      if without_back.empty?
        redirect_back(fallback_location: "/")
      else
        redirect_back(**without_back.last.merge(fallback_location: "/"))
      end
    else
      super
    end
  end

  # detect postbacks for sudo actions using redirect_to :back (which would break)
  def sudo_redirect_to_back?(args)
    args == [:back] && params[:sudo_referrer].present?
  end

  # Redirects to login and sets the return_to to the argument.
  def redirect_to_login(return_to = nil)
    # Block fuzzing that triggers 500 errors in Varnish due to buffer
    # overflows with huge URLs.
    if return_to && URI.encode_www_form_component(return_to).bytesize > MAX_URL_LOGIN_REDIRECT_LENGTH
      return_to = nil
    end
    url_options = return_to ? { return_to: return_to } : {}
    redirect_to login_url(url_options)
  end

  # Redirects to the dashboard.
  def redirect_home
    redirect_to home_url
  end

  # The most recently selected context, aka what dashboard the user
  # will see when going "home" while logged in.
  def saved_context
    session[:context] if session && logged_in?
  end

  # Used to redirect to a URL given in a param if it is considered safe. By
  # default only onsite URL are considered safe. Additional safe hosts can be
  # passed as an option to allow offsite redirects.
  #
  # to      - String URL, usually from params[:to]
  # options - Optional Hash passed to ActionController::Base#redirect_to. The
  #           below options are used by safe_redirect_to itself and will be
  #           deleted before calling ActionController::Base#redirect_to. Please
  #           see ActionController::Base#redirect_to for a full description of
  #           the ActionController::Base#redirect_to specific options.
  #           :fallback        - The redirection URL if `to` points to a
  #                              disallowed off-site URL.
  #           :allow_hosts     - An array of hosts that can be redirected to.
  #                              By default safe_redirect_to only allows
  #                              redirects to onsite hosts (default: []).
  #           :allow_query     - Allow query string for offsite hosts
  #                              (default: false)
  #           :allow_fragment  - Allow fragment for offsite hosts
  #                              (default: false)
  #
  # Returns nothing.
  def safe_redirect_to(to, options = {})
    fallback = options.delete(:fallback) || "#{request.base_url}/"
    to ||= fallback
    allow_hosts = options.delete(:allow_hosts) || []
    allow_query = options.delete(:allow_query)
    allow_fragment = options.delete(:allow_fragment)

    parsed_url = Addressable::URI.parse(to)
    onsite_absolute_url =
      parsed_url.absolute? &&
      %w[https http].include?(parsed_url.scheme) &&
      parsed_url.userinfo.nil? &&
      parsed_url.host == request.host &&
      (parsed_url.port.nil? || parsed_url.port == request.port)

    onsite_relative_url =
      parsed_url.relative? &&
      parsed_url.userinfo.nil? &&
      (parsed_url.host.nil? || parsed_url.host == request.host) &&
      (parsed_url.port.nil? || parsed_url.port == request.port)

    allowed_offsite_absolute_url =
      parsed_url.absolute? &&
      %w[https http].include?(parsed_url.scheme) &&
      parsed_url.userinfo.nil? &&
      allow_hosts.include?(parsed_url.host) &&
      parsed_url.port.nil? &&
      (parsed_url.fragment.nil? || allow_fragment) &&
      (parsed_url.query.nil? || allow_query)

    if onsite_absolute_url || onsite_relative_url
      parsed_url.host = request.host
      parsed_url.scheme = request.scheme
      parsed_url.port = request.port if Rails.env.development? # allow custom ports in developent
      redirect_to parsed_url.to_s, options
    elsif allowed_offsite_absolute_url
      redirect_to parsed_url.to_s, options
    else
      err = BadRedirect.new("Sketchy redirect URL")
      Failbot.report_user_error(err)
      GitHub.dogstats.increment("safe_redirect_to", tags: ["action:fallback", "error:sketchy_url"])
      redirect_to fallback, options
    end
  rescue Addressable::URI::InvalidURIError
    err = BadRedirect.new("Invalid redirect URL")
    Failbot.report_user_error(err)
    GitHub.dogstats.increment("safe_redirect_to", tags: ["action:fallback", "error:invalid_url"])
    redirect_to fallback, options
  end

  ##
  # Filters

  def force_email
    if logged_in? && current_user.email.blank?
      flash[:error] = "You’ll need to add an email address to your account."
      redirect_to settings_email_preferences_url
    end
  end

  # Version all fragment caches
  def fragment_cache_key(key)
    prefix = GitHub.fragment_cache_version
    ActiveSupport::Cache.expand_cache_key(key.is_a?(Hash) ? url_for(key).split("://").last : key, prefix)
  end

  # Set Time.zone to the clients browser zone we detect via JavaScript.
  # See app/assets/javascripts/github/behaviors/timezone.coffee
  def with_user_timezone
    old_zone = Time.zone

    begin
      tz = cookies[:tz].to_s.dup.force_encoding("utf-8")
      raise ArgumentError.new("bad TZ encoding") if !tz.valid_encoding?

      if zone = ActiveSupport::TimeZone[cookies[:tz].to_s]
        Time.zone = zone
      end
    rescue ArgumentError => err
      Failbot.report(
        err,
        "gh.request.tz_string": cookies[:tz].b,
        "gh.request.tz_encoding": cookies[:tz].encoding,
      )
    end

    yield
  ensure
    # Reset zone back to its original state.
    # Default zone is set to "UTC" in `config/initializers/libraries.rb`.
    Time.zone = old_zone
  end

  # Before filter to setup request related globals. GitHub.context and
  # Failbot.context need to be populated with basic request metadata. This
  # should be registered as early in the filter chain as possible.
  #
  # Returns nothing.
  def setup_request_context
    # counts the number of times the current user _would_ be loaded if we eager fetched it here
    GitHub.dogstats.increment("experiment.current_user", tags: ["loaded:lazy", "api:false"])

    T.cast(GH.context, GH::Context::DefaultContext).identity_context = self
    GitHub.context.push(initial_request_context)
    Failbot.push(initial_failbot_context)
    CRubyCrashInfo.info = <<~INFO
      gh.request_id: #{env["HTTP_X_GITHUB_REQUEST_ID"]}
      method: #{request.request_method}
      path: #{request.fullpath}
      remote_ip: #{request.remote_ip}
      worker_pid: #{Process.pid}
      worker_request_count: #{GitHub.unicorn_worker_request_count}
      worker_started_at: #{GitHub.unicorn_worker_start_time}
    INFO
    SensitiveData.context.push(initial_sensitive_data_context)
  end

  # The initial context to populate GitHub.context when the request starts.
  #
  # Maybe overridden in subclasses to add additional debugging metadata. Be
  # sure to call super and merge the hash onto the existing data.
  #
  # Returns a Hash.
  def initial_request_context
    request_url =
      "#{request.protocol}#{request.host_with_port}#{request.fullpath}" rescue nil

    context = {
      actor_ip: request.remote_ip,
      user_agent: request.user_agent.to_s.dup.force_encoding(Encoding::UTF_8).scrub!,
      connections: ApplicationRecord.connection_info,
      country_code: request.env["HTTP_X_COUNTRY"],
      from: "%s#%s" % [params[:controller], params[:action]],
      method: request.try(:request_method),
      request_id: request_id,
      server_id: Rack::ServerId.get(request.env),
      request_category: request_category,
      controller: params[:controller],
      controller_action: params[:action],
      url: request_url,
      client_id: persistent_client_id,
      referrer: request.referrer,
      device_cookie: cookies[:_device_id],
      is_robot: robot?,
    }

    controller = GitHub::TaggingHelper.controller(request.env)
    action = GitHub::TaggingHelper.action(request.env)
    method = GitHub::TaggingHelper.request_method(request.env)

    if controller && action && method
      context[:db_call_source_datadog_tags] = [
        "source_type:request",
        "controller:#{controller}",
        "action:#{action}",
        "method:#{method}",
        "source:request-#{method}-#{controller}-#{action}",
      ]
    end

    context[:current_tenant] = GitHub::CurrentTenant.get&.slug if GitHub.multi_tenant_enterprise?
    context
  end

  # The initial context to populate Failbot.context when the request starts.
  #
  # Returns a Hash.
  def initial_failbot_context
    return @initial_failbot_context if defined?(@initial_failbot_context)

    env = request.try(:env) || {}
    context = {
      "http.request.header.accept": env["HTTP_ACCEPT"],
      "code.function": params[:action],
      "rails.controller.action": params[:action],
      "code.namespace": self.class,
      "rails.controller.name": self.class,
      "gh.db.connection_map": ApplicationRecord.connection_info,
      "gh.request.device_cookie": cookies[:_device_id],
      "http.request.header.accept_language": env["HTTP_ACCEPT_LANGUAGE"],
      "process.parent_pid": Process.ppid,
      "gh.process.parent.started_at": GitHub.unicorn_master_start_time,
      "http.method": request.try(:request_method),
      "gh.oauth.access.id": logged_in? && current_user.oauth_access.try(:id),
      "gh.repo.is_private": current_repository.try(:private?),
      "rails.version": Rails.version,
      "http.request.header.referrer": request.try(:referrer),
      "client.address": request.try(:remote_ip),
      "gh.repo.name_with_owner": current_repository.try(:name_with_owner),
      "gh.repo.id": current_repository.try(:id),
      "gh.request.category": request_category,
      "gh.request_id": env["HTTP_X_GITHUB_REQUEST_ID"],
      "gh.request.wait_duration": env[GitHub::TaggingHelper::REQ_WAIT_TIME],
      "gh.request.start_time": Time.now.utc,
      "service.instance.id": Rack::ServerId.get(env),
      "gh.request.session_map": session.try(:to_hash),
      "gh.request.is_stateless": stateless_request?,
      "url.full": Rack::RequestLogger.url_for_logging(request.url),
      "gh.actor.login": current_user.try(:login),
      "gh.actor.id": current_user.try(:id),
      "gh.actor.spammy": current_user.try(:spammy?),
      "http.request.header.user_agent": env["HTTP_USER_AGENT"],
      "session.id": user_session.try(:id),
      "process.pid": Process.pid,
      "http.server.request.count": GitHub.unicorn_worker_request_count,
      "gh.process.started_at": GitHub.unicorn_worker_start_time,
      "gh.timezone.name": Time.zone.name,
      "gh.actor.is_robot": robot?,
    }

    request.filtered_parameters.each do |key, value|
      context["http.request.parameters.#{key}"] = value unless value.is_a?(Proc) # Failbot doesn't support procs
    end

    context[:"gh.tenant.slug"] = GitHub::CurrentTenant.get&.slug if GitHub.multi_tenant_enterprise?
    context[:"gh.tenant.id"] = GitHub::CurrentTenant.get&.id if GitHub.multi_tenant_enterprise?

    if user_session.try(:impersonator).present?
      context[:"gh.impersonator.login"] = user_session.impersonator.login # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
      context[:"gh.impersonator.id"] = user_session.impersonator.id # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end

    @initial_failbot_context = context
  end

  # The initial context to populate SensitiveData.context when the request starts.
  #
  # May be overridden in subclasses to track additional sensitive data. Be
  # sure to call super and merge the hash onto the existing data.
  #
  # Returns a Hash.
  def initial_sensitive_data_context
    context = {
      # repo name is sensitive when it's private
      repo: current_repository && current_repository.private? ? current_repository.name_with_owner : nil, # rubocop:disable GitHub/DoNotAllowNameWithOwner name_with_owner is ok when used for instrumentation
      remote_ip: request.try(:remote_ip),
    }

    # A _device_id is a randomly generated cookie set during sign in and never expires. If a _device_id were knowingly associated with a user,
    # that information could be used to bypass device verification if the username/password is also known. It would also be able to perform
    # one of the required steps for 2FA recovery.
    if logged_in?
      context[:device_cookie] = cookies[:_device_id]
    end

    context
  end

  # Internal: Log
  #
  # data   - A Hash of key/value pairs to log in addition to the
  #          standard logging data
  # blk    - Execute a block that we wrap with log messages measuring the
  #          block execution.
  def log(data, &blk)
    GitHub::Logger.log(data, &blk)
  end

  # Internal: Store application specific data for this request to be logged.
  #
  # Returns nothing.
  def initialize_log_data
    context = initial_failbot_context
    context_data = context_log_data(context)
    log_data.merge!(context_data)
  end

  def context_log_data(context)
    log_data = {
      user: context[:"gh.actor.login"],
      user_spammy: context[:user_spammy],
      repo: context[:repo],
      oauth_access_id: context[:oauth_access_id],
      user_session_id: context[:"session.id"],
      time_zone: context[:"gh.timezone.name"],
      controller: context[:"rails.controller.name"],
      action: context[:"rails.controller.action"],
      stateless: context[:stateless],
    }

    log_data.merge!(
      "gh.actor.login": current_user&.login,  # rubocop:disable GitHub/DoNotAllowLogin - we want the suffix for EMU users here for logging reasons
      "gh.actor.name": current_user&.display_login,
      "gh.actor.id": current_user&.id,
    )

    log_data
  end

  # Determine the domain used for setting cookies.
  # According to new cookie standards in RFC 6265, there is now no need to add a leading '.' to a cookie domain for the cookie to apply to a subdomain.
  # i.e. a cookie domain of '.github.com' and 'github.com' mean the same thing.
  def cookie_domain
    return GitHub.host_name if GitHub.enterprise?

    # Note: GitHub.host_name_with_tenant can also include the port, but this isn't supported for the domain attribute in the cookie.
    # For example, the value might be something like `github.localhost:80` when starting the server in a codespace.
    return GitHub.host_name_with_tenant.split(":").first if Rails.env.development?

    GitHub.host_name_with_tenant
  end

  # Sets a cookie for the entire .github.com domain if the user is logged in
  # used for oauth apps to know whether to automatically redirect.
  def set_login_cookie
    logged_in_value   = logged_in? ? "yes" : "no"
    dotcom_user_value = logged_in? ? current_user.login : nil # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1310

    if cookies[:logged_in] != logged_in_value
      cookies[:logged_in] = {
        value: logged_in_value,
        expires: 1.year.from_now,
        domain: cookie_domain,
      }
    end

    if cookies[:dotcom_user] != dotcom_user_value
      if dotcom_user_value
        cookies[:dotcom_user] = {
          value: dotcom_user_value,
          expires: 1.year.from_now,
          domain: cookie_domain,
        }
      else
        cookies.delete(:dotcom_user, domain: cookie_domain)
      end
    end
  end

  # These are used for nginx logging.
  def set_user_headers
    response.headers["X-GitHub-User"] = current_user.login if logged_in? # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1339
    response.headers["X-GitHub-Session-Id"] = user_session.id.to_s if user_session
  end

  def set_rails_version_header
    response.headers["X-Rails-Version"] = Rails.version if site_admin?
  end

  # Caps the current page for paginated requests
  def cap_pagination
    if cap_pagination? && over_pagination_limit?
      GitHub.dogstats.increment("pagination_cap", tags: ["via:web"])
      render_404
    end
  end

  # Only cap pagination for numeric page numbers outside of Enterprise
  def cap_pagination?
    !GitHub.enterprise? && params[:page].to_s =~ NUMERIC_PAGE_PATTERN
  end

  def over_pagination_limit?
    current_page > max_pagination_page
  end

  helper_method :at_pagination_limit?
  def at_pagination_limit?
    current_page == max_pagination_page
  end

  def enforce_oauth_scope
    return unless logged_in? && current_user.using_oauth?
    render_404 unless adequate_oauth_scope(current_user.scopes)
  end

  def authorize_content(kind, data = {})
    action_to_authorize = data.delete(:action_to_authorize) || action_name
    authorization = ContentAuthorizer.authorize(current_user, kind, action_to_authorize, data)

    if authorization.has_email_verification_error?
      render_email_verification_required
    elsif authorization.failed?
      return render_404 unless block_given?
      yield(authorization)
    end
  end

  def required_oauth_scopes
    %w(user repo).freeze
  end

  def adequate_oauth_scope(scopes)
    scopes = scopes.map &:to_s
    (required_oauth_scopes - scopes).empty?
  end

  def live_updates_enabled?
    # Check global live updates switch first
    return false unless GitHub.live_updates_enabled?

    # No anonymous live update connections
    return false unless logged_in?

    # No live update connections if login wasn't with a session
    return false unless user_session

    # Otherwise, its enabled for all users
    true
  end
  helper_method :live_updates_enabled?

  # GitHub staff get a special cookie `staffonly` set to `yes`
  # The cookie is also used by nginx to redirect to Lab if the cookie
  # is set to `true` instead of `yes`. Once we have garage.github.com
  # working, hopefully we can phase out nginx redirect and the `true`
  # value.
  def set_employee_cookie
    if cookie = GitHub::StaffOnlyCookie.read(cookies)
      # if the cookie is valid and current, we update it
      set_employee_only_cookie(user: cookie.user, for_lab: cookie.for_lab?)
    elsif logged_in? && GitHub::StaffOnlyCookie.allowed_user?(current_user)
      # Set the "staffonly" cookie on the .github.com domain. This will be sent
      # to *.github.com domains and is used to authenticate requests to lab
      # environments other than "lab" (staff1).
      set_employee_only_cookie(user: current_user, for_lab: false)
    end
    true
  end

  # Only folks with a valid cookie can use the staff-only fe.
  # Only staff get the cookie set, but it lingers after logout
  # for testing the login page.
  #
  # Returns true to skip the filter, or redirects the request.
  def employee_only_unicorn
    # if this isn't an employee unicorn, return true
    return true unless GitHub.employee_unicorn?
    # if the cookie is valid and current, return true
    return true if GitHub::StaffOnlyCookie.read(cookies)

    # otherwise, kick them back to genpop
    GitHub::StaffOnlyCookie.delete!(cookies)
    # delete the tempoary Kubernetes cookie here too
    cookies.delete(:haproxy_backend)
    redirect_to "https://github.com"
  end

  def set_employee_only_cookie(user:, for_lab:)
    if cookie = GitHub::StaffOnlyCookie.generate(user: user, for_lab: for_lab)
      cookie.save!(cookies)
      # Default to canary for staff
      cookies[:haproxy_backend] = "canary" if should_set_haproxy_backend_to_canary?(cookies, user)
    end
  end

  def should_set_haproxy_backend_to_canary?(cookies, user)
    return false unless GitHub.flipper[:staff_cookie_default_to_canary].enabled?(user)
    return false unless user.employee?

    cookies[:staff_canary_opt_out] != "true" && GitHub.kubernetes_backend_available?
  end

  # before_action to hide dotcom only features
  def dotcom_required
    render_404 if GitHub.enterprise?
  end

  # before_action to disable color modes switching
  # For example:
  #   before_action :disable_color_modes, only: [:enterprise]
  def disable_color_modes
    request.env["gh_color_modes_disabled"] = true
  end

  # before_action to load all color mode theme stylesheets
  # For example:
  #   before_action :all_color_mode_themes
  def all_color_mode_themes
    request.env["gh_color_modes_all_themes"] = true
  end

  # before_action to hide GitHub Enterprise Server only features
  def enterprise_required
    render_404 unless GitHub.enterprise?
  end

  # before_action to hide showcase on Enterprise only if not enabled by the admin
  def showcase_disabled
    render_404 if GitHub.enterprise? && !GitHub.showcase_enabled?
  end

  # before_action for actions only available when GitHub Connect is available
  def require_dotcom_connection_enabled
    render_404 unless GitHub.dotcom_connection_enabled?
  end

  # before_action for actions only available when custom pre-receive hooks are available
  def require_custom_pre_receive_hooks_enabled
    render_404 unless GitHub.pre_receive_hooks_enabled?
  end

  # before_action to ensure the actor has a given feature flag enabled
  def ensure_actor_feature_flag_enabled(actor, flag)
    flag_enabled = actor.feature_enabled?(flag)
    GitHub.dogstats.increment("glb.request.feature_flagged", tags: [
      "flag:#{flag}", "enabled:#{flag_enabled}", "controller:#{params[:controller]}", "action:#{params[:action]}"
    ])
    render_404 unless flag_enabled
  end

  # Is this a request for the gist application?
  def gist_request?
    false
  end
  helper_method :gist_request?

  # Helper methods to determine if the current request is being made by a robot,
  # and if so, which one.
  def robot?
    GitHub.robot?(request.user_agent.to_s)
  end
  helper_method :robot?

  # Marks timeout errors as being the client's fault for the duration of the
  # block. All timeout exceptions are rescued and a 403 response is sent back.
  # Timeout exceptions are not reported to Failbot.
  def timeout_client_error(message = nil)
    yield
  rescue Object => boom # rubocop:todo Lint/GenericRescue
    raise if !timeout_error?(boom) || performed?
    message ||= "error: too big or took too long to generate"
    render status: 403, plain: message
  end

  # Overridden in AbstractRepositoryController. Many non-repository scoped layout
  # templates need this helper.
  def repository_offline?
    false
  end
  helper_method :repository_offline?

  # Deprecated: Should request be considered stateless? Does it use any cookies?
  #
  # Maybe overridden in subclasses to add safelist certain actions as
  # stateless.
  #
  # This functionality should be considered deprecated. Stateless endpoints
  # are better off not inheriting from ApplicationController which has many
  # assumptions about browser clients.
  #
  # Current Usage
  # * Atom feeds (consider moving to api.github.com)
  #
  # Security note: stateless requests have no CSRF protection.
  #
  # Returns true or false.
  def stateless_request?
    false
  end
  helper_method :stateless_request?

  def disable_session
    request.session_options[:skip] = true
  end

  # Per-request unique identifier generated by the Rack::RequestId middleware
  def request_id
    request.env[Rack::RequestId::GITHUB_REQUEST_ID]
  end
  helper_method :request_id

  def referrer
    request.headers["Referer"]
  end
  helper_method :referrer

  def internal_or_direct_referrer?
    return true unless request.referrer.present?

    return GitHub.host_name.include?(Addressable::URI.parse(request.referrer).host) if Rails.env.development?
    Addressable::URI.parse(request.referrer).host == GitHub.host_name
  rescue Addressable::URI::InvalidURIError
    false
  end

  # Header passed by GLB indicating the region in which the request originally landed
  def glb_edge_region
    request.headers["X-GLB-Edge-Region"]
  end
  helper_method :glb_edge_region

  # make User/Repo feature flag and experiment methods available as controller/helper/filter methods
  #
  # NOTE: Keep this at the bottom, after any other methods are defined,
  # so conflicts can be caught
  include ApplicationController::FeatureFlagsDependency

  def current_user_orgs
    logged_in? ? current_user.organizations : []
  end
  helper_method :current_user_orgs

  protected

  def check_ofac_sanctions(target: current_user, redirect_url: nil)
    current_user_allowed = !current_user&.has_any_trade_restrictions?
    target_allowed = current_user_allowed && (
      target.blank? || # no need to check if no target was given
      current_user == target || # we already checked current_user
      !target.has_any_trade_restrictions?
    )

    return if target_allowed

    is_organization = current_user_allowed && target&.organization?

    if is_organization
      flash[:trade_controls_organization_billing_error] = true
    else
      flash[:trade_controls_user_billing_error] = true
    end

    yield if block_given?

    if redirect_url
      redirect_to(redirect_url) unless performed?
    elsif is_organization
      redirect_to(org_root_path(target)) unless performed?
    else
      redirect_to(billing_url) unless performed?
    end
  end

  # Public: Screens a given actor for various trade sanctions and ensures that the actor is good to proceed
  # with commercial interactions.
  #
  # This method combines two distinct checks:
  # 1. `check_ofac_sanctions` checks if a specific actor is restricted by virtue of being in an embargoed country or region.
  # 2. `check_actor_screening_status` screens and checks if an actor's billing info is matched on MSFT SDN (Specially Designated Nationals) list.
  #
  # @param target [Object] - The actor (User, Organization, or Business) who is the target for the checks.
  #
  # @param redirect_url [String, nil] (optional) - A URL to redirect to at the end of the checks.
  #
  # @param feature_type [Symbol] (optional) - Specifies the context or feature within which the check is being made.
  # Default is :default, but can be customized as per the specific feature requirements. Any new feature type
  # must be included in AccountScreeningProfile::FEATURE_TYPE_ALLOW_LISTS.
  #
  # @param sdn_redirect [Boolean] (optional) - By default SDN screening checks does not redirect after the checks.
  # This forces a redirect if set to true.
  #
  # @param blk [Proc] (optional) - An optional block to be executed after the checks.
  #
  # Returns nothing.
  def check_trade_compliance(target: current_user, redirect_url: nil, feature_type: :default, sdn_redirect: false, &blk)
    check_ofac_sanctions(target: target, redirect_url: redirect_url)
    check_actor_screening_status(target: target, redirect_url: redirect_url, feature_type: feature_type, sdn_redirect: sdn_redirect, &blk)
  end

  def ensure_billing_enabled
    render_404 unless GitHub.billing_enabled?
  end

  def ensure_two_factor_sms_enabled
    render_404 unless GitHub.two_factor_sms_enabled?
  end

  def ensure_ip_allowlists_available
    render_404 unless GitHub.ip_allowlists_available?
  end

  def github_internal_referrer_route
    referrer = Addressable::URI.parse(request.referrer)
    if referrer && referrer.domain == request.domain
      Rails.application.routes.recognize_path(Addressable::URI.escape(referrer.path))
    end
  rescue ActionController::RoutingError, Addressable::URI::InvalidURIError
    # Referrer is invalid so cannot be internal route
    nil
  end

  sig { returns T::Hash[Symbol, T.untyped] }
  memoize def referring_params
    Rails.application.routes.recognize_path(request&.referrer) || {}
  end

  sig { returns(MagicShell) }
  memoize def magic_shell
    MagicShell.new(current_user, current_repository)
  end
  helper_method :magic_shell

  private

  def max_pagination_page
    GitHub.max_ui_pagination_page
  end

  def default_render(*args)
    raise NotImplementedError,
      "Do not use Rails implicit render. Explicitly call `render` in #{self.class.name}##{action_name}.\n  " +
        "render \"#{controller_path}/#{action_name}\"\n\n"
  end

  # Maintain compatibility with backported behavior
  # The native Rails 5+ version won't set Content-Type to text/plain
  # if it's already been set (by respond_to, for instance)
  # Prevents info leakage; see #66171 for more detail
  def render(*args)
    if args.first.is_a?(Hash)
      options = args.first
      if options[:plain]
        options[:content_type] = Mime[:text]
      elsif options[:html]
        options[:content_type] = Mime[:html]
      end
      if options[:text]
        raise NotImplementedError, "render text: is not supported in Rails 5+"
      end
    elsif args.first.is_a?(String)
      args[0] = args[0].dup
    end

    data = report_api_insights_information(args)
    return super { json => data } if data

    super
  end

  # Private: Instantiate a site visitor using the `_octo` cookie as a persistent
  # identifer.
  def find_current_visitor
    Analytics::Visitor.with_octolytics_id(cookies[:_octo])
  end

  # Private: Generate a new site visitor and store the visitor's ID in the
  # `_octo` cookie for the entire .github.com domain.
  def create_current_visitor
    visitor = Analytics::Visitor.create

    GitHub.dogstats.increment("cookie", tags: ["action:set", "type:_octo"])

    # This cookie is also used in Javascript client side, so it is explicitly
    # not marked as `httponly`
    cookies[:_octo] = {
      value: visitor.octolytics_id,
      expires: 1.year.from_now,
      domain: cookie_domain,
    }

    visitor
  end

  # Private: Returns boolean whether to protect from CSRF. Override in
  # subclasses to skip for specific cases.
  def verify_authenticity_token?
    !stateless_request?
  end

  # Private: checks to see if there are any CSP exceptions that should be added
  # to a given request. This method was extracted purely to prevent duplicate
  # code. It is still the calling controller's responsibility to add a filter
  # that calls this method. This will raise an error if called but CSP_EXCEPTIONS
  # is not defined.
  def add_csp_exceptions
    exceptions = self.class.const_get(:CSP_EXCEPTIONS)
    SecureHeaders.append_content_security_policy_directives(request, exceptions)
  end

  def set_client_uid
    GitHub.context.push(client_uid: params[:client_uid])
    Audit.context.push(client_uid: params[:client_uid])
  end

  # Requires content to be served on an admin frontend (behind okta network
  # gateway). Redirects admin requests when served on non-admin frontends.
  def require_admin_frontend
    # Restricted front-ends aren't used/available in dev, test, and enterprise.
    return unless GitHub.admin_frontend_enabled?
    # Staging lab is a special snowflake, as it is wired up as a production
    # enviroment, but isn't actually holding production data. There is no
    # staging-lab specific configuration we can edit to set things like
    # `admin_frontend_enabled` to false. So, we special case it here to not
    # require an admin front-end.
    return if GitHub.staging_lab?
    # No need to redirect if the request is to an admin front-end.
    return if GitHub.admin_host?
    # If the current_user has no access to administrative functionality we 404
    # for normal users and 403 for employees.
    return render_403_for_employees unless admin_frontend_accessible?

    filtered_params = params.to_unsafe_hash.except!(*::UrlHelper::DANGEROUS_KEYS)
    url = url_for(filtered_params.merge!({ host: GitHub.admin_host_name }))
    safe_redirect_to(url, allow_query: true, allow_hosts: [GitHub.admin_host_name])
  end

  # Public: Captures request params along with current timestamp and provides interface for getting
  # Spamurai signals. See SignupController#create_account and user.create event for example usage.
  #
  # Returns a SpamuraiFormSignals instance.
  def spamurai_form_signals
    cleaned_params = request.params.deep_dup
    denylist = [:controller, :action, :password, :password_confirmation, :old_password]

    denylist.each do |key|
      cleaned_params.delete(key)
      cleaned_params[:user].delete(key) if cleaned_params[:user]
    end

    @spamurai_form_signals ||= SpamuraiFormSignals.create(request_params: cleaned_params)
  end

  # Public: Return the persistent client ID from the _octo cookie, if present.
  # This is different than the session ID because it is not reset when the user
  # logs out.
  def persistent_client_id
    Analytics::OctolyticsId.coerce(cookies[:_octo]).unversioned
  rescue Analytics::OctolyticsId::CoercionError
    nil
  end

  def require_xhr
    head :not_acceptable unless request.xhr?
  end

  def initialize_hydro_context
    if hydro_context[:enabled]
      hydro_context.merge!({
        request_category: request_category,
        controller: self.class.name,
        controller_action: action_name,
        client_id: persistent_client_id,
        session_id: user_session&.id,
        current_user: current_user&.login, # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
        current_user_id: current_user&.id,
        analytics_tracking_id: current_user&.analytics_tracking_id,
        server: GitHub.local_host_name,
      })

      if current_repository
        hydro_context.merge!({
          current_repo: current_repository.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner nwo is ok when used for instrumentation
          current_repo_id: current_repository.id,
          current_repo_visibility: (current_repository.private? ? :PRIVATE : :PUBLIC),
        })
      end
    end
  end

  def disable_hydro_request_logging
    hydro_context[:enabled] = false
  end

  def hydro_context
    request.env[GitHub::HydroMiddleware::CONTEXT] ||= {}
  end

  def referral_params
    {
      ref_page: params[:ref_page],
      ref_cta: params[:ref_cta],
      ref_loc: params[:ref_loc]
    }
  end

  def with_referral_params(**options)
    referral_params.merge(options)
  end

  def mandatory_message_check
    return unless GitHub.enterprise?
    return unless logged_in?
    return unless MandatoryMessage.exists?
    return if MandatoryMessage.user_viewed?(current_user)

    render "mandatory_messages/show", layout: "layouts/dashboard"
  end

  def track_time(metric: nil, tags: [])
    timer = Timer.start
    result = yield
    metric = "#{controller_name}_controller.dist.time" if metric.nil?

    GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags)
    result
  end

  def format_link_header(bundle)
    asset_bundles = AssetBundlesHelper.new(current_user)
    path = asset_bundles.bundle_url(bundle)

    "<#{path}>; rel=preload; crossorigin=anonymous; as=script"
  end

  def set_header_for_no_index_and_no_follow
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def clear_current_repository
    @current_repository = nil
    @nav_breadcrumb = nil
  end

  # Enables cross-package query checking for staff
  # See: GitHub::SQLCheckers::DomainIsolation::*StatementChecker classes
  def cpq_check
    if (real_user_site_admin? || employee?) && GitHub.flipper[:cpq_check].enabled?(current_user)
      GitHub.context.push(cpq: true)
    end
  end

  def with_request_time_budget_control
    GitHub::RequestDurationManager.enable_time_budget_control
  end

  def non_emu_required
    render_404 if current_user.is_enterprise_managed?
  end

  def emu_required
    render_404 unless current_user.is_enterprise_managed?
  end

  # We want to ensure browsers cache ajax requests separetely from regular HTML responses.
  # This allows us to use the same URL to serve both HTML and JSON.
  # This header is already being added by our nginx config in https://github.com/github/github/blob/faa32626bac7dfc3b3dd028e478766c87e586a24/config/kustomize/base/production/unicorn-api/configs/nginx.conf#L58
  # but having it here as well makes it easier to understand and also adds the same behavior to all environments (proxima/GHES).
  def set_vary_requested_with
    add_headers_to_vary(["X-Requested-With"])
  end

  sig { params(headers: T::Array[String]).void }
  def add_headers_to_vary(headers)
    existing_vary = response.headers["Vary"].to_s.split(",").map(&:strip)
    response.headers["Vary"] = (existing_vary + headers).uniq.join(", ")
  end
end
