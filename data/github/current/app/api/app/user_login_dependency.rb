# typed: true
# frozen_string_literal: true

module Api::App::UserLoginDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  AUTH_VIA_QUERY_PARAMS_BLOG_POST_URL = "#{GitHub.developer_site_url}/changes/2020-02-10-deprecating-auth-through-query-param"

  # Public: Fetches the currently logged in user for this request.
  #
  # Returns either a User instance or nil.
  def current_user
    return @current_user if defined?(@current_user)

    attempt_login

    if @current_user
      actor_context = @current_user.event_context(prefix: :actor)
      GitHub.context.push(actor_context)
      Audit.context.push(actor_context)
    end

    Time.zone = timezone_for_request(@current_user)
    @current_user
  end

  def attempt_login
    @current_user = nil
    login_from_api_auth
  end

  def attempt_login_from_integration
    @current_user = nil
    login_from_integration_assertion
  end

  # returns the identity of the tenant-bound proxima service, which serves as an actor for the purpose
  # of rate limiting only.
  def proxima_service_identity
    return @proxima_service_identity if defined?(@proxima_service_identity)

    return unless GitHub.flipper[:proxima_service_rate_limiting].enabled?
    return unless request_credentials.proxima_service_token_present?

    verified_token = ProximaServiceToken.verify(request_credentials.proxima_service_token)
    if verified_token.valid?
      GitHub.dogstats.increment("api.proxima_service_token", tags: ["valid:true"])
    else
      GitHub.dogstats.increment("api.proxima_service_token", tags: ["valid:false"])
      return
    end
    verified_token.identity
  end

  private

  # Looks up the User for the current request using Basic Authentication.
  #
  # Halts with a 401 if the User is not authenticated.
  # Halts with a 403 if the User is not authenticated and over the auth limit.
  # Returns nothing.
  def login_from_api_auth
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

    if result.success?
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
  rescue GitHub::SMS::Error => e
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

    if assertion.valid?
      self.current_integration = assertion.integration
    else
      response_code = assertion.error == :not_found ? 404 : 401
      deliver_error! response_code, message: assertion.error_message
    end
  end

  def api_auth
    return @api_auth if defined? @api_auth
    @api_auth = GitHub::Authentication::Attempt.new(
      allow_integrations:                 true,
      allow_user_via_granular_actor:         true,
      from:                               authenticating_from,
      # login is ok in lookups
      login:                              request_credentials.login, # rubocop:disable GitHub/DoNotAllowLogin
      password:                           request_credentials.password,
      otp:                                request_credentials.otp,
      token:                              request_credentials.token,
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
