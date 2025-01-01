# typed: true
# frozen_string_literal: true

require "oauth_util"

class OauthController < ApplicationController
  ALLOW_ACCESS_TOKEN_REQUESTS_PER_HOUR = 2000

  include ControllerMethods::Oauth
  include OauthHelper
  include ApplicationController::JsonDependency

  # Ensure that we parse json params before the other filters to ensure that
  # the params hash contains valid data for all requests.
  before_action :try_parse_json_params

  # Ensure we attempt to rate limit device authorization requests before making
  # database calls.
  before_action :rate_limit_device_access_token_requests, only: [:access_token]

  before_action :add_account_picker_override,                    only: [:request_access]
  before_action :authorization_required,                         only: [:request_access, :authorize, :account_picker]
  before_action :find_application!,                              only: [:request_access, :authorize, :access_token, :request_device_authorization, :account_picker]
  before_action :reject_applications_owned_by_spammy!,           only: [:request_access, :authorize, :access_token, :request_device_authorization, :account_picker]
  before_action :ensure_application_can_send_callback_requests!, only: [:request_access, :authorize]
  before_action :check_visibility,                               only: [:request_access, :authorize]
  before_action :check_eligibility,                              only: [:request_access, :authorize]
  before_action :validate_requested_scopes,                      only: [:request_access, :authorize]
  before_action :conditional_sudo_filter,                        only: [:authorize]
  before_action :add_csp_exceptions,                             only: [:request_access, :authorize]
  before_action :reject_dangerous_requests,                      only: [:request_access, :authorize]
  before_action :reject_suspended_applications,                  only: [:request_access, :authorize]
  before_action :validate_redirect_uri,                          only: [:request_access, :authorize]
  before_action :reject_invalid_redirect_uri,                    only: [:request_access, :authorize]

  # We are handling SSO and enforcing external identity sessions and IP allowlists
  # elsewhere in the code.
  #
  # This is due to the fact that there isn't a single SSO target.
  #
  # See OauthController#request_access -> `if show_sso_selection?`
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  around_action :select_write_database, only: [:authorize, :access_token]

  skip_after_action :block_non_xhr_json_responses, only: [:access_token, :request_device_authorization]

  layout "layouts/oauth_authorization"
  javascript_bundle :oauth
  stylesheet_bundle :oauth

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:request_access, :authorize],
    if: :logged_in?,
    max: 50,
    ttl: 1.hour,
    key: :absolute_authorize_rate_limit_key,
    log_key: "oauth-abs-authorize"

  rate_limit_requests \
    only: [:access_token],
    max: :access_token_max_tries,
    ttl: 1.hour,
    key: :application_access_token_rate_limit_key,
    log_key: "oauth-application-access-token"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Permissions,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Lodge,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:request_access]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Lodge,
    ApplicationRecord::Mysql5,
    only: [:access_token]

  # Public: Authorize an application's request to act on behalf of a user.
  #
  # GET  - Show the user a view to allow/deny this application access.
  #      - github.com/login/oauth/authorize?client_id=<key>&...
  #
  # Renders a view or redirects back to the application's callback URL.
  def request_access # rubocop:todo GitHub/UseRestfulActions
    return head :forbidden unless request.get?

    # Is this application allowed to skip user authorization? Immediately grant
    # with the pre-registered scopes and redirect with a code.  Bounty:
    # https://github.com/github/github/issues/117804
    if Apps::Privileged.capable?(:can_auto_approve_oauth_authorization, app: application)
      options = { user_session: user_session }

      if application.uses_scopes?
        scope = (application.scopes && application.scopes.join(","))
        options.merge!(scope: scope, requested_scope: scope)
      end

      @access = application.grant(
        current_user, options
      )
      GitHub.dogstats.increment("oauth.conversion", tags: ["type:auto"])

      return redirect_back_with_access_code(@access, @redirect_uri)
    end

    strip_analytics_query_string

    if account_picker_required? # Double-check the user is who they want to be.
      return redirect_to oauth_select_account_path(account_picker_params)
    end

    if show_sso_selection?(application)
      cap_unauthorized_saml_orgs = unauthorized_saml_organizations_for_application
      more_than_one_target = (cap_unauthorized_saml_orgs.count > 1)
      GitHub.dogstats.increment("oauth.sso.required", tags: ["multiple_targets:#{more_than_one_target}"])

      cap_unauthorized_saml_orgs.each do |org|
        allow_external_redirect_after_post(provider: org.saml_provider)
      end

      cap_authorized_saml_organizations = cap_filter.satisfied_resources(current_user&.organizations, only: :saml)

      suggested_org = saml_for_user.saml_organizations.find { |o| o.display_login.downcase == params[:org]&.downcase }

      render "oauth/identity_management/sso", layout: "layouts/session_authentication", locals: {
        application:                     application,
        cap_authorized_saml_organizations:   cap_authorized_saml_organizations,
        form_data:                       captured_form_data_via_enforcement,
        return_to_url:                   request.url,
        cap_unauthorized_saml_organizations: cap_unauthorized_saml_orgs,
        skip_sso_url:                    skip_sso_url(request.original_url),
        suggested_org:                   suggested_org
      }

      return
    end

    # Immediately authorize (send an access code) applications that have
    # already been granted access and any of the following are true:
    #   - The new scope request is less permissive than what has already been
    #     authorized.
    #   - The scope parameter was not included.
    #   - The GitHub App is not requesting additional granular user permissions.
    #
    # NOTE: If params[:scope] isn't included in the request, the scopes for
    # what has already been authorized will be used.

    @authorization = current_user.oauth_authorizations.find_by(application: application)

    # We enforce rate limits for applications that have been previously
    # authorized and will automatically create an access and redirect. Rate
    # limiting prevents unbounded access creation for misconfigured
    # applications that redirect back to the authorize endpoint endlessly.
    unless requesting_prompt?
      if less_permissive? && !authorize_rate_limited? && current_user_matching_request?
        GitHub.dogstats.increment("oauth.conversion", tags: ["type:auto"])
        # If no scopes were requested then we use the set that has been
        # authorized.
        scope = params.has_key?(:scope) ? @scopes : @authorization.scopes
        @access = application.grant(
          current_user,
          { scope: scope, requested_scope: params[:scope], user_session: user_session },
        )

        return redirect_back_with_access_code(@access, @redirect_uri)
      end
    end

    track_authorize_metrics

    if application.is_a?(Integration)
      view = create_view_model(
        Oauth::AuthorizeIntegrationView,
        authorization: @authorization,
        application:   application,
        params:        params,
        redirect_uri:  @redirect_uri,
        session:       session,
        scopes:        [],
        form_submission_path: oauth_authorize_path,
        rate_limited:  authorize_rate_limited?(increment: false),
        redirect_uri_specified: params.key?(:redirect_uri)
      )

      render "oauth/authorize_integration", locals: { view: view }
    else
      view = create_view_model(
        Oauth::AuthorizeView,
        authorization: @authorization,
        application: application,
        params: params,
        redirect_uri: @redirect_uri,
        session: session,
        scopes: @scopes,
        form_submission_path: oauth_authorize_path,
        rate_limited: authorize_rate_limited?(increment: false),
        unauthorized_saml_organizations: unauthorized_saml_organizations_for_application,
        unauthorized_ip_allowlist_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations, only: [:ip_allowlist, :external_conditional_access_policy]),
        redirect_uri_specified: params.key?(:redirect_uri),
      )
      render "oauth/authorize", locals: { view: view }
    end
  end

  def request_device_authorization # rubocop:todo GitHub/UseRestfulActions
    response_options = DeviceAuthorizationRequest.process(application, params, request.ip)
    status = :ok

    if response_options.key?(:error)
      status = :bad_request # https://tools.ietf.org/html/rfc6749#section-5.2
      log_data[:error] = response_options[:error]
    end

    render_token_response(response_options, status: status)
  end

  # Public: Authorize an application's request to act on behalf of a user.
  #
  # POST - Handle the form POST to grant this application access to the user by
  #        redirecting to the application's callback URL with an oauth code.
  #
  # Renders a view or redirects back to the application's callback URL.
  def authorize # rubocop:todo GitHub/UseRestfulActions
    if oauth_access_authorized?
      track_authorize_metrics
      grant_options = {
        scope: @scopes,
        requested_scope: params[:scope],
        integration_version_number: params[:integration_version_number],
        user_session: user_session,
      }
      if params[:redirect_uri_specified]
        grant_options[:redirect_uri] = params[:redirect_uri]
      end

      @access = application.grant(current_user, grant_options)

      # Once a user has explicitly authorized an application we clear the limit
      # to minimize collateral damage (ex. a developer testing their OAuth
      # application flow).
      remove_rate_limit_key(redirect_loop_authorize_rate_limit_key)

      instrument_integration_listing

      log_data[:verification_code] = secret_last_eight(@access.code)
      redirect_back_with_access_code(@access, @redirect_uri)
    else
      GitHub.dogstats.increment("oauth.conversion", tags: ["error:access_denied"])
      redirect_back_with_error application,
        error: :access_denied,
        error_description: "The user has denied your application access.",
        error_uri: GitHub.developer_help_url + "/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#access-denied",
        state: params[:state]
    end
  end

  def access_token # rubocop:todo GitHub/UseRestfulActions
    params[:client_secret] = client_secret # Override before we process
    response_options = OauthAccessTokenRequest.process(application, log_data, params, entry_point: :oauth_controller_access_token)

    render_token_response(response_options)
  end

  def success # rubocop:todo GitHub/UseRestfulActions
    render plain: "Success"
  end

  # Public: Continue forward with OAuth flow with a given account chosen by the user.
  #
  # POST - Handle the form POST to set that the user has chosen an account to continue with.
  #
  # Redirects to the oauth_request_path with the original params and an account picker state param,
  # preventing the account picker from re-appearing.
  def account_picker # rubocop:todo GitHub/UseRestfulActions
    redirect_to oauth_request_path(account_picker_params)
  end

  private

  def access_token_max_tries
    ALLOW_ACCESS_TOKEN_REQUESTS_PER_HOUR
  end

  def application_access_token_rate_limit_key
    default_rate_limit_key + ":#{application.class.to_s[0]}:#{application.id}"
  end

  def rate_limit_device_access_token_requests
    return false unless params[:grant_type] == DeviceAuthorizationGrant::GRANT_TYPE

    prefix = "device_auth_token_request"
    suffix = Digest::SHA256.base64digest("#{params[:client_id]}:#{params[:device_code]}")

    rate_limit_key = "#{prefix}:#{suffix}"
    rate_limiter = IncrementalBackoffRateLimiter.check(rate_limit_key, interval: DeviceAuthorizationGrant::INTERVAL)

    return true unless rate_limiter.at_limit?
    GitHub.dogstats.increment("slow_down", tags: ["action:access_token", "subject:device_authorization"])

    response_options = {
      error: :slow_down,
      error_description: "Too many requests have been made in the same timeframe.",
      error_uri: GitHub.developer_help_url,
      interval: rate_limiter.interval
    }

    log_data[:error] = :slow_down
    render_token_response(response_options)
  end

  STATELESS_ACTIONS = %w(access_token request_device_authorization)

  # Allow remote form POSTs to STATELESS_ACTIONS
  def stateless_request?
    STATELESS_ACTIONS.include?(action_name) || super
  end

  def access_denied
    args = params.delete(:allow_signup) == "false" ? { allow_signup: false } : {}

    args.tap do |arg|
      arg[:return_to] = oauth_request_path(params.permit!.to_hash.symbolize_keys)
      arg[:client_id] = params[:client_id]

      if params[:login].present?
        arg[:login] = params[:login]
      end
    end

    redirect_to login_path(args)
  end

  def validate_requested_scopes
    @scopes = OauthAccess.normalize_scopes(params[:scope])
  end

  def oauth_access_authorized?
    %w[1 Approve].include? params[:authorize]
  end

  def refresh_tokens_enabled?
    application.is_a?(Integration) && application.user_token_expiration_enabled?
  end

  def redirect_back_with_access_code(access, redirect_uri)
    response_params = {
      code: access.code,
      state: params[:state],
    }
    if application.github_owned?
      browser_session_id = access.browser_session_id(user_session)
      response_params[:browser_session_id] = browser_session_id
    end

    redirect_back(OauthUtil.redirect_url(redirect_uri, response_params))
  end

  def redirect_back_with_error(app, params)
    redirect_back(OauthUtil.redirect_url(app.callback_url.to_s, params))
  end

  def redirect_back(url)
    redirect_url = url

    if should_meta_redirect?
      render "oauth/meta_refresh_redirect_to_application", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
    else
      redirect_to(redirect_url)
    end
  end

  def should_meta_redirect?
    referrer = begin
      Addressable::URI.parse(request.referrer)
    rescue Addressable::URI::InvalidURIError
      nil
    end
    same_origin_request = referrer && referrer.host == request.host

    # All same origin OAuth controller requests are initiated with a POST that
    # is subject to our `form-action` CSP policy. By checking
    # `same_origin_request` we can force a meta redirect to allow for offsite
    # redirects. These same origin initiated flows include:
    #  * OAuth dance initiated and required a user to login
    #  * OAuth dance initiated and required a user to authorize the application
    !!same_origin_request
  end

  memoize def application
    get_application(client_id)
  end

  def find_application!
    return render_404 if application.nil?

    case application
    when Integration
      log_data[:integration_id] = application.id
    when OauthApplication
      log_data[:oauth_application_id] = application.id
    end

    application
  end

  def ensure_application_can_send_callback_requests!
    return unless application.is_a?(Integration)
    return if application.can_send_callback_requests?

    render plain: "This GitHub App must be configured with a callback URL", status: 403
  end

  def get_redirect_uri(app, redirect_uri)
    # Only normalize applications with one callback URL to maintain legacy
    # behavior for existing applications.
    normalize = !app.strict_callback_url_validation?

    redirect_uri = app.try(:callback_url) if redirect_uri.blank?
    normalize ? Addressable::URI.parse(redirect_uri).normalize.to_s : redirect_uri
  end

  def reject_applications_owned_by_spammy!
    render_404 if application&.spammy?
  end

  def reject_suspended_applications
    return unless application.suspended?

    error_description = "Your application has been suspended. Please visit #{contact_url}."
    docs_path = application.is_a?(Integration) ? "/apps/using-github-apps/authorizing-github-apps" : "/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#application-suspended"

    redirect_back_with_error application,
      error: :application_suspended,
      error_description: error_description,
      error_uri: GitHub.developer_help_url + docs_path,
      state: params[:state]
  end

  def validate_redirect_uri
    begin
      @redirect_uri = get_redirect_uri(application, params[:redirect_uri])
    rescue Addressable::URI::InvalidURIError
      render "oauth/invalid_redirect_uri"
    end
  end

  def reject_invalid_redirect_uri
    unless OauthUtil.valid_redirect_uri?(application, @redirect_uri)
      render "oauth/invalid_redirect_uri"
    end
  end

  # Private: Prepares the token response in either JSON, XML, or Form values.
  #
  #   # json format
  #   token_response(:json, :access_token => 'foo') # =>
  #     {"access_token":"foo"}
  #   # xml format
  #   token_response(:xml, :access_token => 'foo') # =>
  #     <OAuth><access_token>foo</access_token></OAuth>
  #   # :form is default.
  #   token_response(:access_token => 'foo') # =>
  #     access_token=foo
  #
  # params_or_format - Either a Symbol format (:json, :xml, :form), or
  #                     a Hash of params if :form is desired.
  # params           - Hash of params.
  #
  # Returns String response.
  def token_response(params_or_format, params = nil)
    format = \
      if params.nil?
        params = params_or_format
        :form
      else
        params_or_format
      end
    case format
    when :form then params.to_query
    when :json then GitHub::JSON.encode(params)
    when :xml  then params.to_xml(root: :OAuth,
        dasherize: false, skip_types: true, skip_instruct: true)
    end
  end

  def secret_last_eight(secret)
    secret = secret.to_s
    return secret if secret.length < 8

    secret.to_s[-8..-1]
  end

  def track_authorize_metrics
    metric = request.post? ? "conversions" : "impressions"

    type = if (request.get? && request_organization_approval?(user: current_user, application: application, scopes: @scopes)) ||
      (request.post? && params[:org_policy])
      "org-policy"
    else
      "simple"
    end

    GitHub.dogstats.increment("oauth", tags: ["metric:#{metric}", "type:#{type}"])
  end

  def client_id
    params[:client_id] || client_id_via_basic_auth
  end

  def client_id_via_basic_auth
    app_creds_via_basic_auth.first
  end

  def client_secret
    params[:client_secret] || client_secret_via_basic_auth
  end

  def client_secret_via_basic_auth
    app_creds_via_basic_auth.second
  end

  def app_creds_via_basic_auth # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @app_creds if defined?(@app_creds)

    basic = Rack::Auth::Basic::Request.new(request.env)

    @app_creds = if basic.provided? && basic.basic?
      basic.credentials
    else
      []
    end
  end

  # Private: Rate limit the authorize action, mostly to minimize unbounded
  # OAuth token creation for misconfigured/poorly coded OAuth applications that
  # endlessly call OauthController#authorize when a failure occurs in their
  # application.
  #
  # increment - The Boolean value that determines if the rate limiter should be
  # incremented.
  #
  # Returns true when this application has exceeded the rate limit and false
  # otherwise.
  def authorize_rate_limited?(increment: true)
    options = {
      max_tries: 10,
      ttl: 1.hour,
      stealthy: !increment,
    }

    at_limit = if increment
      rate_limit_increment(redirect_loop_authorize_rate_limit_key, options)
    else
      rate_limit_check(redirect_loop_authorize_rate_limit_key, options)
    end.at_limit?

    if increment && at_limit
      GitHub.dogstats.increment("rate_limited", tags: ["action:authorize", "subject:oauth"])
    end
    at_limit
  end

  def redirect_loop_authorize_rate_limit_key
    "oauth:authorize:#{current_user.id}:#{client_id}"
  end

  # Regardless of permissiveness, provide an absolute limit to the number of
  # authorize requests within a reasonable timeframe.
  def absolute_authorize_rate_limit_key
    "oauth-abs:authorize:#{current_user.id}:#{client_id}"
  end

  def add_csp_exceptions
    SecureHeaders.override_x_frame_options(request, SecureHeaders::XFrameOptions::SAMEORIGIN)
    SecureHeaders.append_content_security_policy_directives(
      request,
      frame_ancestors: [SecureHeaders::PolicyManagement::SELF],
    )
  end

  def render_token_response(response_options, status: :ok)
    respond_to do |format|
      format.any(:html, :url_encoded_form) do
        render body: token_response(response_options), content_type: "application/x-www-form-urlencoded", status: status
      end

      format.xml do
        render xml: token_response(:xml, response_options), status: status
      end

      format.json do
        render json: token_response(:json, response_options), status: status
      end
    end
  rescue ActionController::UnknownFormat => e
    medias = Api::AcceptedMediaTypes.new(request.accept, "")

    # Allow GitHub API JSON formats to receive a valid JSON response.
    if medias.acceptable? && medias.json?
      return render(json: token_response(:json, response_options), status: status)
    end

    raise e
  end

  def requesting_prompt?
    params[:prompt] == "consent"
  end

  def less_permissive?
    return false unless @authorization

    case @authorization.application_type
    when "Integration"
      @authorization.upgradedable_without_user_permission?
    else
      @authorization.safely_less_permissive?(@scopes)
    end
  end

  def current_user_matching_request?
    return true unless params.key?(:login)
    current_user.display_login == params[:login]
  end

  def skip_sso_url(request_url)
    uri = Addressable::URI.parse(request_url)

    additional = { skip_sso: true }
    uri.query_values = (uri.query_values || {}).merge(additional)

    uri.to_s
  end

  # Private: Determine if we should give the user the choice to change which account is the `current_user` before
  # continuing forward. Only select users and OAuth apps go through this flow based on:
  #
  # - Has the flow requested to skip the account picker (i.e. after the user has already picked their account)?
  # - Is the account switcher is available for the user?
  #
  # Returns true or false.
  def account_picker_required?
    # strip skip_account_picker if the request isn't originating from "github"
    # https://github.com/github/ecosystem-apps/issues/4397
    if !request.referrer.present? || URI(request.referrer).host != request.host
      params.delete(:skip_account_picker)
      GitHub.dogstats.increment("oauth.skip_account_picker_stripped")
    end

    if current_user
      skip_account_picker = params[:skip_account_picker] == "true"
      return false if skip_account_picker

      # Prioritize showing the prompt if it's demanded by the app, but after we check for a skip
      return true if params[:prompt] == "select_account"

      # General availability based on the Account Switcher feature
      return true if account_switcher_helper.enabled? && account_switcher_helper.stashed_accounts.valid.any?

      # GitHub mobile for iOS/Android
      non_http_callback = !/\Ahttps?:\/\//.match?(application.callback_url)
      return true if non_http_callback

      return false
    end

    skip_account_picker = params[:skip_account_picker] == "true"
    return false if skip_account_picker

    non_http_callback = !/\Ahttps?:\/\//.match?(application.callback_url)
    return false unless non_http_callback

    # Setting a query parameter to verify to the request_access action that the user has picked an account
    requires_account_picker = params[:as_state].nil? || params[:as_state] != user_session.id.to_s
    requires_account_picker
  end

  def add_account_picker_override
    # use db-based feature flag checks if current_user exists
    return if current_user

    # As a pre-flight check to prevent extra database hits, ensure only capable OAuth apps add additional pre-login parameters.
    # The actual check is implemented in `account_picker_required?`.
    if Apps::Privileged.capable?(:oauth_add_account_picker_override, app: application)
      # Upon successful session creation, this will hint that the user has verified their identity and can skip the account switcher UI.
      params[:skip_account_picker] = true
    end
  end
end
