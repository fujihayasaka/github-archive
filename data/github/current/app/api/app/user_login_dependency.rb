# typed: true
# frozen_string_literal: true

module Api::App::UserLoginDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  include GH::Auth::IdentityContext

  AUTH_VIA_QUERY_PARAMS_BLOG_POST_URL = "#{GitHub.developer_site_url}/changes/2020-02-10-deprecating-auth-through-query-param"

  # Public: Fetches the currently logged in user for this request.
  #
  # Returns either a User instance or nil.
  def current_user
    return @current_user if defined?(@current_user)

    # counts the number of times the current user is _actually_ loaded
    GitHub.dogstats.increment("experiment.current_user", tags: ["loaded:eager", "api:true"])
    attempt_login

    if @current_user
      actor_context = @current_user.event_context(prefix: :actor)
      GitHub.context.push(actor_context)
      Audit.context.push(actor_context)
    end

    Time.zone = timezone_for_request(@current_user)
    @current_user
  end

  def domain_actor
    current_user
  end

  def attempt_login
    GitHub.tracer.in_span("api.app-before", kind: :internal, attributes: {
      "code.namespace" => "attempt_login"
    }) do |_span|
      @current_user = nil
      login_from_api_auth
    end
  end

  def attempt_login_from_integration
    @current_user = nil
    login_from_integration_assertion
  end

  def attempt_login_from_spark
    @current_user = nil
    login_from_spark_token

    # regular auth is still supported, so fall back to that if the user wasn't found from a Spark-Bearer header
    unless @current_user
      login_from_api_auth
    end
  end

  # returns the identity of the tenant-bound proxima service, which serves as an actor for the purpose
  # of rate limiting only.
  def proxima_service_identity
    return @proxima_service_identity if defined?(@proxima_service_identity)

    return unless FeatureFlag.vexi.enabled_or_raise?(:proxima_service_rate_limiting) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return unless request_credentials.proxima_service_token_present?

    verified_token = ProximaServiceToken.verify(request_credentials.proxima_service_token)
    verified_token.valid? ? increment_proxima_service_token(true) : increment_proxima_service_token(false)

    @proxima_service_identity = verified_token.identity
  end

  private

  def increment_proxima_service_token(valid)
    GitHub.dogstats.increment("api.proxima_service_token", tags: ["valid:#{valid}"])
  end

  # Looks up the User for the current request using Basic Authentication.
  #
  # Halts with a 401 if the User is not authenticated.
  # Halts with a 403 if the User is not authenticated and over the auth limit.
  # Returns nothing.
  def login_from_api_auth
    # If the request was previewed by the gateway, compare "no credentials" result
    # TODO: Remove this when the gateway is no longer in preview mode.
    if FeatureFlag.vexi.enabled_or_raise?(:gateway_preview_authn_science) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub::Experiment.new "gateway_preview_no_credentials" do |e|
        e.run_if { request.env.key?("HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT") }

        e.context({
          request_path: request.path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
          request_credentials_via_params: request_credentials.via_params?,
          request_credentials_login_password_present: request_credentials.login_password_present?,
          request_gateway_authn_result: env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"],
        })

        e.use { api_auth.credentials_present? && !request_credentials.via_params? }
        e.try { env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] != "no_credentials" }

        e.ignore do
          if FeatureFlag.vexi.enabled?(:gateway_preview_authn_science_ignore, default: false)
            # the gateway can't validate credentials which it doesn't support
            return true if env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] == "unsupported_credentials"
            return true if env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] == "error"
          end
        end
      end.run
    end

    return unless api_auth.credentials_present?
    result = api_auth.result

    # Reject all requests using authentication via query params
    # https://github.com/github/ecosystem-apps/issues/404
    # https://github.com/github/ecosystem-apps/issues/970
    if request_credentials.via_params?
      GitHub.dogstats.increment("api.authentication", tags: ["reason:access_token_via_params"])

      deliver_error!(
        400,
        message: "Must specify access token via Authorization header. #{AUTH_VIA_QUERY_PARAMS_BLOG_POST_URL}",
        documentation_url: "/v3/#oauth2-token-sent-in-a-header",
      )
    end

    auth_success = result.success?

    # If the request was previewed by the gateway, compare api-auth result.
    # This covers: PATv1, PATv2, OAuth, Installation, and App User to Server credentials.
    # TODO: Remove this when the gateway is no longer in preview mode.
    if FeatureFlag.vexi.enabled_or_raise?(:gateway_preview_authn_science) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub::Experiment.new "gateway_preview_api_auth" do |e|
        e.run_if { request.env.key?("HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT") && !request_credentials.via_params? }

        e.context({
          request_path: request.path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
          request_credentials_via_params: request_credentials.via_params?,
          request_credentials_login_password_present: request_credentials.login_password_present?,

          # lots of details around the authentication attempt result for debugging mismatches
          attempt_programmatic_access_type: api_auth.programmatic_access_type,
          attempt_token_type: api_auth.token_type,
          attempt_result: result.failure_reason,
          user_id: result.user&.id,
          access_id: result.user&.oauth_access&.id
        })

        if result&.user&.is_a?(Bot)
          # Add installation context if the user is a Bot (i.e. this is some flavor of GitHub App token). repeated
          # calls merge the passed in context with any existing context, so this is additive to the previous call.
          e.context({
            installation_id: result.user&.installation&.id,
            installation_type: result.user&.installation&.class&.name,
          })
        end

        e.use { auth_success ? "valid_credentials" : "invalid_credentials" }
        e.try { env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] }

        e.ignore do |control, candidate|
          if FeatureFlag.vexi.enabled?(:gateway_preview_authn_science_ignore, default: false)
            # the gateway can't validate credentials which it doesn't support
            return true if control == "invalid_credentials" && candidate == "unsupported_credentials"
            return true if candidate == "error"
          end
        end
      end.run
    end

    if auth_success
      @current_user = result.user
      @oauth = @current_user.oauth_access
      @current_programmatic_access = @current_user.programmatic_access

      @oauth || @current_programmatic_access
    elsif result.suspended_failure?
      reject_for_suspended_user!
    elsif result.suspended_oauth_application_failure?
      reject_for_suspended_oauth_application!
    elsif result.suspended_integration_failure?
      reject_for_suspended_integration!
    elsif result.suspended_installation_failure?
      reject_for_suspended_installation!(result.message)
    elsif result.application_owned_by_spammy_failure?
      reject_for_application_owned_by_spammy!(result.message)
    elsif result.attribution_only_system_identity_failure?
      deliver_error! 401, message: result.message
    elsif result.two_factor_partial_sign_in?
      ensure_user_has_otp
      ensure_two_factor_request_instrumented
      response.headers["X-GitHub-OTP"] = "required; #{result.two_factor_type}"
      deliver_error! 401,
        message: "Must specify two-factor authentication OTP code.",
        documentation_url: "/v3/auth#working-with-two-factor-authentication"
    elsif result.message
      deliver_error(400,
        message: result.message,
        documentation_url: "/v3/auth#basic-authentication")
    else
      reject_failed_login!(api_auth.result)
    end
  rescue GitHub::Messaging::Error => e
    message =
      "We tried sending an SMS to your configured number, but #{e.message}." +
      " Please contact support at if you continue to have problems."
    deliver_error!(500, message: message)
  end

  # Internal: Attempts to authenticate the requesting
  # integration using a signed assertion token.
  #
  # Sets the current_user to the integration's bot if successful.
  # Otherwise responds with a 401 describing why the assertion
  # was invalid.
  def login_from_integration_assertion
    assertion = Api::IntegrationAssertion.new(env)
    assertion_valid = assertion.valid?

    if FeatureFlag.vexi.enabled_or_raise?(:gateway_preview_integration_credentials_science) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      GitHub::Experiment.new "gateway_preview_integration_credentials" do |e|
        e.run_if { request.env.key?("HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT") && assertion_valid }

        e.context({
          request_path: request.path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],

          # App client IDs are NOT sensitive values, so it is safe to log them.
          integration_client_id: assertion.integration&.key,
          integration_id: assertion.integration&.id,

          # log the first two segments of the JWT for investigative purposes. Importantly,
          # this does not include the signature, so it is safe to log. The signature is the
          # piece that establishes trust from an authentication perspective, so we should
          # no log it.
          first_two_segments: assertion.value&.split(".")&.first(2)&.join("."),
        })

        # using a static string here for any outcome as the gateway should skip these values today
        e.use { "unsupported_credentials" }
        e.try { env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] }
      end.run
    end

    if assertion_valid
      self.current_integration = assertion.integration
    else
      response_code = assertion.error == :not_found ? 404 : 401
      deliver_error! response_code, message: assertion.error_message
    end
  end

  def login_from_spark_token
    user, app_owner_login = SparkRuntime::TokenService.decrypt_jwt_claims!(raw_header: env["HTTP_AUTHORIZATION"])

    # if the request was previewed by the gateway, compare spark auth result
    # TODO: remove this when the gateway is no longer in preview mode
    if FeatureFlag.vexi.enabled?(:gateway_preview_spark_authn_science, default: false)
      GitHub::Experiment.new "gateway_preview_spark_auth" do |e|
        e.run_if { request.env.key?("HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT") && request.env["HTTP_AUTHORIZATION"]&.include?("Spark-Bearer") }

        e.context({
          request_path: request.path,
          request_method: request.request_method,
          request_id: env["HTTP_X_GITHUB_REQUEST_ID"],
        })

        # use a static string here for any outcome as the gateway should skip these values today
        e.use { "unsupported_credentials" }
        e.try { env["HTTP_X_GITHUB_GATEWAY_AUTHN_RESULT"] }
      end.run
    end
    if user.present?
      @current_user = user
      @app_user = app_owner_login
      @oauth = @current_user.oauth_access
      @current_programmatic_access = @current_user.programmatic_access

      GitHub.context.push(auth: "spark_bearer")
      Audit.context.push(auth: "spark_bearer")
      log_data[:auth] = "spark_bearer"

      @oauth || @current_programmatic_access
    end
  end

  def api_auth
    return @api_auth if defined? @api_auth
    @api_auth = GitHub::Authentication::Attempt.new(
      allow_integrations:                 true,
      allow_user_via_granular_actor:      true,
      from:                               authenticating_from,
      # login is ok in lookups
      login:                              request_credentials.login, # rubocop:disable GitHub/DoNotAllowLogin
      password:                           request_credentials.password,
      otp:                                request_credentials.otp,
      token:                              request_credentials.token,
      exchange_token:                     request_credentials.internal_exchange_token,
      ip:                                 remote_ip,
      user_agent:                         user_agent,
      request_id:                         env["HTTP_X_GITHUB_REQUEST_ID"],
      password_auth_blocked:              password_auth_blocked?,
      url:                                Rack::RequestLogger.url_for_logging(request.url),
    )
  end

  def authenticating_from
    if respond_to? :source
      return source
    end

    :api_other
  end

  def request_credentials
    @request_credentials ||= Api::RequestCredentials.from_env(env)
  end

  # Idempotent method of sending the user a 2FA OTP SMS. login_from_api_auth
  # can be called multiple times and we don't want to send multiple SMS.
  def ensure_user_has_otp
    return if defined? @sent_otp
    user = api_auth.attempted_user
    return unless user.two_factor_sms_enabled?
    return unless request_sends_otp_sms?
    GitHub.dogstats.increment("send_two_factor_sms", tags: ["from:login_from_api_auth"])
    user.send_two_factor_sms(callsite: :authorization_ensure_user_has_otp)
    @sent_otp = true
  end

  # Idempotent method of instrumenting that we requested a 2FA code.
  # login_from_api_auth can be called multiple times and we don't want to
  # instrument this twice.
  def ensure_two_factor_request_instrumented
    return if defined? @two_factor_request_instrumented
    user = api_auth.attempted_user
    user.instrument_two_factor_requested note: "From GitHub API", two_factor_type: "otp"
    @two_factor_request_instrumented = true
  end
end
