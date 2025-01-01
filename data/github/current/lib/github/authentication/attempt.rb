# typed: true
# frozen_string_literal: true

require "authnd-client"

class GitHub::Authentication::Attempt
  OAUTH_BASIC_PASSWORD = /^(x-oauth-basic)?$/

  UNENFORCED_AUTHENTICATION_LIMIT_FAILURES = %i(missing_creds duplicate_password blank_otp not_a_regular_user external_auth_token_required api_with_password_auth weak_password)
  UNAUDITABLE_FAILURES = %i(missing_creds duplicate_password blank_otp not_a_regular_user external_auth_token_required api_with_password_auth weak_password first_emu_admin_recovery_code_required)

  DEPRECATED_WEAK_PASSWORD_ACTIONS = %w(api)

  attr_accessor :login, :password, :otp, :ignore_otp, :token, :from, :metadata, :attempt_type, :octolytics_id,
    :allow_integrations, :allow_user_via_granular_actor, :current_device_id, :password_auth_blocked, :exchange_token

  # Instantiate an Attempt object.
  #
  # data - A Hash containing information about the attempt. Any data other than
  #        the following keys will be used for logging/rate limiting.
  #
  #        :login      - The login of the user authenticating.
  #        :password   - The password of the user authenticating.
  #        :otp        - The current 2FA OTP of the user authenticating.
  #        :token      - The access token of the user authenticating.
  #        :from       - Symbol describing the origin of the attempt.
  #        :octolytics_id - the device ID (if available)
  #        :current_device_id - the AuthenticatedDevice device ID for this attempt
  #        :allow_integrations  - Whether the caller supports server to
  #                                      server GitHub App authorization checks
  #                                      (default false).
  #        :allow_user_via_granular_actor - Whether the caller supports user to
  #                                      server GitHub App authorization checks
  #                                      (default false).
  #        :exchange_token - JWT issued by authnd which is a short-lived equivalent to a user-provided access
  #                                 token. Currently, only used on an experimental basis but will be graduated to
  #                                 inhabit the :token param.
  def initialize(data)
    @login        = data.delete(:login)
    @password     = data.delete(:password)
    @otp          = data.delete(:otp)
    @token        = data.delete(:token)
    @exchange_token = data.delete(:exchange_token)
    @from = data.delete(:from) do
      raise ArgumentError, "from must be specified"
    end
    if data[:user_agent]
      data[:user_agent] = data[:user_agent].to_s
    end
    @octolytics_id = data.delete(:octolytics_id)
    @current_device_id = data.delete(:current_device_id)
    @password_auth_blocked = data.delete(:password_auth_blocked)
    @social = data.delete(:social)

    # Most callers don't know how to support server to server IntegrationInstallation
    # tokens, so we default to false unless the caller explicitly opts in.
    @allow_integrations =
      !!data.delete(:allow_integrations)

    # Most callers don't know how to support user to server OAuth tokens, so we
    # default to false unless the caller explicitly opts in.
    @allow_user_via_granular_actor =
      !!data.delete(:allow_user_via_granular_actor)

    @metadata = data
  end

  # Are the accumulated credentials sufficient to attempt authentication.
  #
  # Returns true if login and password or a token are present.
  def credentials_present?
    login_password_present_and_supported? || token_present? || exchange_token_present_and_supported_as_primary?
  end

  # Are the username and password both present to attempt authentication? Are we allowing basic auth to be used for the endpoint?
  #
  # Returns true if login and password are present and the endpoint accepts basic auth and false otherwise.
  def login_password_present_and_supported?
    # We ignore the login and password if password auth has
    # been deprecated for this endpoint
    return false if password_auth_blocked?
    login.present? && password.present?
  end

  # Is the token present to attempt authentication?
  #
  # Returns true if a token is present and false otherwise.
  def token_present?
    token.present?
  end

  # Is the internal exchange token present and supported for primary auth?
  #
  # Returns true if the internal exchange token is present and usable for primary authentication.
  def exchange_token_present_and_supported_as_primary?
    return @exchange_token_present_and_supported_as_primary if defined?(@exchange_token_present_and_supported_as_primary)

    @exchange_token_present_and_supported_as_primary =
      exchange_token.present? && GitHub::Authnd::InternalExchangeToken.attemptable?
  end

  # Is this a token-auth attempt?
  #
  # Returns boolean.
  def token_attempt?
    result && @attempt_type == :token
  end

  # Is this a password-auth attempt?
  #
  # Returns boolean.
  def password_attempt?
    result && @attempt_type == :password
  end

  # Attempt to authenticate with the accumulated credentials and instrument the
  # result.
  #
  # Returns a GitHub::Authentication::Result object.
  def result
    return @result if defined? @result

    @result = try_auth
    never_forget

    # temporary logging to help investigate https://github.com/github/repos/issues/16752
    if FeatureFlag.vexi.enabled?(:invalid_token_investigation, attempted_user, default: false) &&
       from?(:git) &&
       @result.failure_reason == :auth_error &&
       @attempt_type == :password

      token_type = AccessTokens.get_token_type(password)

      last_eight = password&.last(8) if token_type != :unknown
      hashed_password = AccessTokens.hash_token(password) if token_type != :unknown

      GitHub.logger.info({
        "message" => "Invalid token investigation",
        "user.login" => attempted_user_login,
        "user.id" => attempted_user_id,
        "last_eight" => last_eight,
        "token_type" => token_type,
        "password_length" => password&.length,
        "hashed_password" => hashed_password,
        "token_description" => AccessTokens.token_description(password),
      })
    end

    @result
  end

  # The user that is attempting to authenticate.
  #
  # Returns a User or nil.
  def attempted_user
    return @attempted_user if defined? @attempted_user
    @attempted_user = User.find_by_login_or_email login
  end

  # Clear memoization of attempted user and other associated memoizations.
  #
  # Returns nothing.
  def clear_attempted_user_memoizations
    @attempted_user = nil
    @attempted_user_login = nil
    @attempted_user_id = nil
    @attempted_user_organization_ids = nil
  end

  def token_type
    @token_type ||=
      if !token && exchange_token_present_and_supported_as_primary?
        begin
          meta = GitHub::Authnd::InternalExchangeToken.unsafe_token_metadata(exchange_token)
          GitHub::Authnd.token_type_from_credential_type_attribute(meta["credential.type"])
        rescue ArgumentError, JWT::DecodeError
          :unknown
        end
      else
        AccessTokens.get_token_type(token)
      end
  end

  def valid_checksum_result
    @valid_checksum_result ||= AccessTokens.valid_checksum_result(token)
  end

  def programmatic_access_type
    @programmatic_access_type ||=
      if token_present?
        AccessTokens.token_description(token)
      elsif exchange_token_present_and_supported_as_primary?
        "Internal exchange token"
      else
        "Unknown"
      end
  end

  private

  def from_web_and_block_weak_password_enabled?(user)
    return @from_web_and_block_weak_password_enabled if defined?(@from_web_and_block_weak_password_enabled)
    @from_web_and_block_weak_password_enabled = from?(:web) &&
      !FeatureFlag.vexi.enabled?(:block_compromised_password_at_sign_in_opt_out, user, default: false)
  end

  def check_weak_password?(user)
    return true if from?(:web) || from?(:sudo)
    from?(:git) && GitHub::ActionRestraint.perform?(
      "compromised_password_check",
      interval: 1.day,
      user_id: user.id,
      from: from.to_s,
    )
  end

  def password_auth_blocked?
    !!@password_auth_blocked
  end

  def send_weak_password_deprecation_warning_actions?
    # for now we only send weak password warning to auth attempts
    # via web and api; git could be added in the future
    from?(:web)
  end

  def block_weak_password_actions?(user)
    # for now we only block weak password for web and api;
    # git could be added in the future after we figure out a
    # notification strategy.
    from_web_and_block_weak_password_enabled?(user)
  end

  def weak_password_check_and_store(user, compromised_password)
    if send_weak_password_deprecation_warning_actions? &&
      !user.password_check_metadata.exact_match? &&
      !user.password_check_metadata.weak? && compromised_password &&
      GitHub::ActionRestraint.perform?(
        "compromised_password_notification",
        interval: 1.week,
        user_id: user.id,
        from: from.to_s,
      )
      AccountMailer.weak_password_warning(user, from.to_s, user_agent: metadata[:user_agent], deadline: user.block_deadline).deliver_later
    end
    # we stat if we found a weak password from git and it hasn't already been
    # noted in the DB yet (through auth from web, api etc).
    if from?(:git) && compromised_password && !user.password_check_metadata.weak?
      GitHub.dogstats.increment("new_git_weak_password", tags: ["action:git"])
    end

    # if compromised_password is nil, we don't want to update the weak password check result
    # we should only clear the weak password check in places where it's intentional (e.g. password resets)
    if !!compromised_password
      ActiveRecord::Base.connected_to(role: :writing) do
        user.update_weak_password_check_result(compromised_password: compromised_password)
      end
    end
  end

  def should_analyze_failed_sign_in?(user)
    # We don't want to analyze bots or orgs
    # as they don't have passwords
    return false if user&.bot?

    # This could get spammy so we avoid analyzing duplicate
    # password failures
    return false if duplicate_password_failure?

    return true if from?(:web) || from?(:sudo)

    # We should always analyze employees to ensure
    # no one is attempting to take over their account
    return true if user&.employee?

    # git/api receives alot of traffic, we sample
    # failed logins for targeted users
    from?(:git) && GitHub::ActionRestraint.perform?(
      "analyze_failed_sign_in",
      interval: 1.hour,
      user: !!user ? user.id : @login,
      from: from.to_s,
    )
  end

  def analyze_failed_sign_in_for_compromised_password(password_result)
    maybe_user = password_result.user || attempted_user
    if should_analyze_failed_sign_in?(maybe_user)
      CompromisedPassword.find_using_password(
        password,
        user: maybe_user,
        action: attempt_stats_tag,
        correct_password: false,
      )
    end
  end

  # Private: Limit the number of sign ins from distinct devices from an unverified IP
  def device_creation_limited?(password_result)
    from?(:web) &&
      password_result.success? &&
      password_result.user.sign_in_analysis_enabled? &&
      !password_result.user.authenticated_devices.where(device_id: current_device_id).exists? &&
      AuthenticationLimit.at_any?(device_creation_login: attempted_user_login, increment: true, actor_ip: metadata[:ip]) &&
      !password_result.user.verified_device_events_from_ip?(metadata[:ip])
  end

  # Private: Limit the number of sign ins from a given device from an unverified IP
  def device_use_limited?(password_result)
    from?(:web) &&
      password_result.success? &&
      password_result.user.sign_in_analysis_enabled? &&
      password_result.user.authenticated_devices.unverified.where(device_id: current_device_id).exists? &&
      AuthenticationLimit.at_any?(device_use_login: attempted_user_login, increment: true, actor_ip: metadata[:ip]) &&
      !password_result.user.verified_device_events_from_ip?(metadata[:ip])
  end

  # Private: Try our credentials against the try_password_auth and or
  # try_token_auth.
  #
  # Returns a Authentication::Result instance.
  def try_auth
    token_result = try_access_token_auth
    if token_result.success? || token_failure?(token_result)
      @attempt_type = :token
      token_result.sign_in_method = :access_token
      return token_result
    end

    if @social.present?
      @attempt_type = :social
      result = try_social_auth
      result.sign_in_method = :social_provider
    else
      @attempt_type = :password
      result = try_password_auth
      result.sign_in_method = :password
    end

    if device_creation_limited?(result)
      return GitHub::Authentication::Result.at_device_auth_limit_failure
    else
      remember_device(result)
    end

    if verified_device_required?(result)
      verification_method = result.user.sign_in_verification_method(result.authenticated_device, metadata[:ip], octolytics_id)
      if verification_method
        result.sign_in_verification_method = verification_method
        GitHub.dogstats.increment("authenticated_device", tags: ["action:challenge", "verification_method:#{verification_method}"])
      else
        result = if device_use_limited?(result)
          GitHub::Authentication::Result.at_device_auth_limit_failure
        else
          GitHub::Authentication::Result.unverified_device_failure(
            user: result.user,
            message: "The current device has not been authorized.",
            authenticated_device: result.authenticated_device,
          )
        end
      end
    end

    if result.success? || result.suspended_failure? || result.unverified_device_failure?
      return result
    end

    if likely_token_failure?(result, token_result)
      @attempt_type = :token
      token_result
    else
      result
    end
  end

  def remember_device(password_result)
    return unless from?(:web)
    return if !password_result.correct_password?
    return unless password_result.user.sign_in_analysis_enabled?

    new_record, authenticated_device = AuthenticatedDevice.find_device_or_create!(
      password_result.user,
      device_id: current_device_id,
      display_name: AuthenticatedDevice.generated_display_name(Browser.new(metadata[:user_agent])),
    )

    if new_record
      tags = ["action:create"]
    else
      tags = ["action:update", "from:password_attempt"]
      tags << "info:no_update_needed" unless authenticated_device.throttled_touch
    end

    GitHub.dogstats.increment("authenticated_device", tags: tags)

    password_result.authenticated_device = authenticated_device
  end

  def weak_password_check_result(password_result)
    if check_weak_password?(password_result.user)
      password_result.has_compromised_password = CompromisedPassword.find_using_password(password, user: password_result.user, action: attempt_stats_tag)
      weak_password_check_and_store(password_result.user, password_result.has_compromised_password)
    end
    # we block sign in from web and api if the weak_password_check_result field timestamp is older than 30 days;
    # we also block web, api and git weak password direct matches.
    if block_weak_password_actions?(password_result.user) && password_result.user.password_check_metadata.should_block?
      password_result = GitHub::Authentication::Result.weak_password_failure(user: password_result.user)
    elsif from?(:git) && password_result.user.password_check_metadata.exact_match?
      password_result = GitHub::Authentication::Result.weak_password_failure(user: password_result.user)
    end
    password_result
  end

  # Private: Attempt to authenticate using login/password.
  #
  # Returns a Authentication::Result instance.
  def try_password_auth
    if !login_password_present_and_supported?
      return GitHub::Authentication::Result.failure(failure_reason: :missing_creds)
    elsif from?(:git) && !GitHub.git_password_auth_supported?
      return GitHub::Authentication::Result.failure(failure_reason: :auth_error)
    elsif GitHub.external_auth_token_required? && from?(:git)
      return GitHub::Authentication::Result.failure(failure_reason: :external_auth_token_required)
    end

    if at_auth_limit?
      return GitHub::Authentication::Result.at_auth_limit_failure
    end

    if from?(:web_api)
      return GitHub::Authentication::Result.web_api_with_password_failure
    end

    password_result = if from?(:sudo)
      GitHub.auth.password_authenticate(login, password)
    else
      GitHub.auth.password_and_otp_authenticate(login, password, otp)
    end

    if password_result.correct_password?
      password_result = weak_password_check_result(password_result)
    else
      analyze_failed_sign_in_for_compromised_password(password_result)
    end

    if password_result.success?
      clear_attempted_user_memoizations
      @attempted_user = password_result.user
      return password_result
    end

    password_result.failure_reason =
      if attempted_user && !attempted_user.user?
        :not_a_regular_user
      elsif password_result.two_factor_partial_sign_in? && password_result&.two_factor_type == "first_admin_recovery_code"
        :first_emu_admin_recovery_code_required
      elsif password_result.two_factor_partial_sign_in? && otp.blank?
        :blank_otp
      elsif password_result.ldap_timeout?
        :ldap_timeout
      # Check for :duplicate_password failures before :invalid_user failures.
      # We want to treat invalid user failures similar to valid user
      # failures with regard to duplicate password attempts. This will
      # prevent collateral damage from IP rate limiting for invalid logins
      # that repeatedly fail authentication with a duplicate password.
      elsif password_result.password_failure? && duplicate_password_failure?
        :duplicate_password
      elsif !GitHub.auth.external? && attempted_user.nil?
        :invalid_user
      else
        password_result.failure_reason || password_result.failure_type
      end

    if at_auth_limit?(password_result)
      GitHub::Authentication::Result.at_auth_limit_failure
    else
      password_result
    end
  end

  def try_social_auth
    GitHub::Authentication::Result.failure(failure_reason: :social_unsupported) unless from?(:web)

    if at_auth_limit?
      return GitHub::Authentication::Result.at_auth_limit_failure
    end

    # if we've gotten to this point, we've been able to look up the user from their email,
    # so we can assume that the user exists and is a regular user - not EMU or first admin
    clear_attempted_user_memoizations
    @attempted_user = @social.user
    GitHub.auth.social_user_authenticate(@attempted_user)
  end

  # Attempt to authenticate using token.
  #
  # Returns a Authentication::Result instance.
  def try_access_token_auth
    access_token_auth_options = {
      allow_integrations: allow_integrations,
      allow_user_via_granular_actor: allow_user_via_granular_actor,
      ip: metadata[:ip],
      user_agent: metadata[:user_agent],
    }

    result = AccessTokens.try_auth(
      from: from,
      token: token,
      exchange_token: exchange_token,
      auth_options: access_token_auth_options
    )

    # With tokens, we don't know which user is trying to auth until it succeeds.
    if result.success?
      clear_attempted_user_memoizations
      @attempted_user = result.user
    end

    result
  end

  # Private: Is this auth attempt over any auth limits?
  #
  # failure - A failed GitHub::Authentication::Result (optional).
  #
  # Returns boolean.
  def at_auth_limit?(failure = nil)
    # skip auth limit checks for invalid logins
    return unless attempted_user_login && GitHub::UTF8.valid_unicode3?(attempted_user_login)

    # separate rate limits for IPs from web vs. non-web
    ip_data = if from == :web
      if GitHub.web_ip_lockouts_enabled?
        { web_ip: metadata[:ip] }
      else
        {}
      end
    else
      { ip: metadata[:ip] }
    end

    password_limit = AuthenticationLimit.at_any?(
      **ip_data.merge(login: attempted_user_login),
      increment: incr_auth_limit?(failure),
      from: from,
    )

    two_factor_limit = AuthenticationLimit.at_any?(
      two_factor_login: attempted_user_login,
      increment: increment_two_factor_authentication_limit?(failure),
      from: from,
      actor_ip: metadata[:ip],
    )

    verify_device_limit = AuthenticationLimit.at_any?(
      verified_device_login: attempted_user_login,
      increment: increment_verify_device_limit?(failure),
      from: from,
      actor_ip: metadata[:ip],
    )

    two_factor_limit || password_limit || verify_device_limit
  end

  # Private: Should the auth limits be incremented for this auth failure?
  #
  # failure - A failed GitHub::Authentication::Result or nil if this is a
  # pre-check.
  #
  # Returns boolean.
  def incr_auth_limit?(failure)
    !(
      failure.nil? ||
      unenforced_authentication_limit_failure?(failure)
    )
  end

  # Private: Should the 2FA auth limit be incremented?
  #
  # failure - A failed GitHub::Authentication::Result or nil if this is a
  # pre-check.
  #
  # Returns boolean.
  def increment_two_factor_authentication_limit?(failure)
    failure.present? &&
    failure.two_factor_partial_sign_in? &&
    otp.present? &&
    otp =~ TwoFactorCredential::OTP_REGEX &&
    !attempted_user.two_factor_recently_valid_otp?(otp)
  end

  # Private: Should the verified device auth limit be incremented?
  #
  # failure - A failed GitHub::Authentication::Result which has a correct
  #  user password but incorrect verified device code (and not 2FA enabled).
  #
  # Returns boolean.
  def increment_verify_device_limit?(failure)
    failure.present? &&
    failure.correct_password? &&
    failure.unverified_device_failure? &&
    !failure.two_factor_partial_sign_in?
  end

  # Private: Does this password auth failure match the last password auth
  # failure from this user?
  #
  # Returns boolean.
  DUPLICATE_PASSWORD_TTL = 1.day
  def duplicate_password_failure?
    return @duplicate_password_failure if defined? @duplicate_password_failure
    @duplicate_password_failure = begin

      # I know, you're going to want to change this to using the ID of the
      # user but we may not have it. Sure a `login` value can change, but
      # there isn't much to gain by gaming this system.
      key = "v3:auth_failure:#{Digest::SHA256.hexdigest(login)}"

      # Try the cache, fall back to KV, write to KV once per day, write to
      # the cache every time.
      previous = memcache.get(key, true)

      tags = { memcached: !!previous, kv: "probably" }
      unless previous
        GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:duplicate_password_failure"])
        previous = GitHub::Authentication::KV.store.get(key).value { nil }
        tags[:kv] = !!previous
      end

      if previous
        cached_password = GitHub::Password.from_hash(previous)
        same_password = cached_password.verify(password).success
      end

      if same_password
        memcache.set(key, previous, DUPLICATE_PASSWORD_TTL, true)
      else
        new_password = GitHub::Password.create(password).to_s
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:duplicate_password_failure"])
          kv_success = GitHub::Authentication::KV.store.try_set(key, new_password, expires: DUPLICATE_PASSWORD_TTL.from_now)
          unless kv_success
            GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :attempt_dupe_password_check, action: :set })
          end
        end
        memcache.set(key, new_password, DUPLICATE_PASSWORD_TTL, true)
      end

      GitHub.dogstats.increment("duplicate_password_detection", tags: tags.map { |k, v| [k, v].join(":") })
      same_password
    end
  end

  # Private: Was this attempt uninteresting and not worth enforcing rate limits?
  #
  # failure - A failed GitHub::Authentication::Result.
  #
  # Returns true if auth failed due to circumstances that are not a security risk.
  def unenforced_authentication_limit_failure?(failure)
    UNENFORCED_AUTHENTICATION_LIMIT_FAILURES.include?(failure.failure_reason)
  end

  # Private: Was this attempt uninteresting and not worth logging?
  #
  # failure - A failed GitHub::Authentication::Result.
  #
  # Returns true if auth failed due to circumstances that are not a security risk.
  def unauditable_failure?(failure)
    UNAUDITABLE_FAILURES.include?(failure.failure_reason)
  end

  # Private: Was this likely a token failure rather than a password failure?
  # We are very flexible with how clients pass token credentials, so it can be
  # ambiguous whether an authentication failure is a password authentication
  # failure or a token authentication failure.
  # For example, Attempt.new(:login => foo, :password => "A1" * 20) will cause
  # both a token authentication failure and a password authentication failure.
  #
  # password_result - An authentication result from try_password_auth
  # token_result - An authentication result from try_token_auth
  #
  # Returns true if the authentication failure was most likely a token
  # authentication failure and false otherwise.
  def likely_token_failure?(password_result, token_result)
    return false unless token_result.token_failure?

    # If either username or password were missing from the password attempt
    # then it is likely a token authentication failure.
    return true if password_result.failure_reason == :missing_creds

    # Since we now know password_result is not :missing_creds, then if the login
    # field was parsed as a token && the password field is "x-oauth-basic" it is
    # likey a token authentication failure.
    return true if token == login && password =~ OAUTH_BASIC_PASSWORD

    # It is very unlikely that a user has a 40 hex character password. So, if it
    # is, we assume it is a token.
    return true if token == password && OauthAccessTokens::Domain.matches_pattern?(password)

    # If we identified that the password looks like an authentication token,
    # then this is likely a token failure.
    (token == password && ServerToServerTokens::Domain.matches_pattern?(token))
  end

  # Private: Whether the token result is a failure that resulted from a valid
  # token, but where the associated user is not allowed to authenticate.
  #
  # token_result - The result after attempting token authentication.
  #
  # Returns true if the authentication failure resulted from the associated user
  # not being allowed to authenticate and false otherwise.
  def token_failure?(token_result)
    return false unless token_result.failure?

    token_result.suspended_failure? ||
      token_result.suspended_oauth_application_failure? ||
      token_result.suspended_integration_failure? ||
      token_result.allow_integrations_failure? ||
      token_result.allow_user_via_granular_actor_failure? ||
      token_result.suspended_installation_failure? ||
      token_result.application_owned_by_spammy_failure? ||
      token_result.attribution_only_system_identity_failure?
  end

  # Private: The token hashed with the default hashing technique for the token
  # type (which is currently Base64-encoded SHA-256 for all types).
  #
  # Returns nil if there was no token and the hashed token otherwise.
  def hashed_token
    @hashed_token ||= AccessTokens.hash_token(token)
  end

  # Private: The login of the user attempting to authenticate.
  #
  # Returns a String User login.
  def attempted_user_login
    @attempted_user_login ||=
      if attempted_user
        attempted_user.login
      elsif login != token
        login
      end
  end

  # Private: The id of the user attempting to authenticate.
  #
  # Returns a User id or nil.
  def attempted_user_id
    @attempted_user_id ||= attempted_user ? attempted_user.id : nil
  end

  # Private: The organization ids of the user attempting to authenticate.
  #
  # Returns an Array of Organization ids or nil.
  def attempted_user_organization_ids
    if attempted_user
      @attempted_user_organization_ids ||= attempted_user.organization_ids
    end
  end

  # Private: Instrument/audit/log the authentication event.
  #
  # Returns nothing.
  def never_forget
    instrument
    log

    if authentication_record_for_sign_in?
      result.user.authentication_records.create!(
        octolytics_id: self.octolytics_id,
        client: :two_factor_partial_sign_in,
        user_agent: metadata[:user_agent],
        authenticated_device: result.authenticated_device,
        ip_address: metadata[:ip],
        location: GitHub::Location.look_up(metadata[:ip]),
      )
    end

    # We send all sign in failures to hydro.
    if result.failure? && from?(:web)
      GlobalInstrumenter.instrument("user.failed_login", {
        actor: attempted_user,
        sign_in_method: result.sign_in_method,
      })
    end

    if auditable_result?(result)
      audit
    end
  end

  # We don't want to log uninteresting authentication events as they
  # only add noise.
  def auditable_result?(result)
    return true if result.weak_password_failure?

    # in enterprise, we want to log all failures
    # so that admins can see exactly what is happening
    unless GitHub.enterprise?
      return false if unauditable_failure?(result)
    end

    result.suspended_failure? || result.password_failure? || result.two_factor_partial_sign_in? || result.social_failure?
  end

  # Private: Instrument authentication event with statsd.
  #
  # Returns nothing.
  def instrument
    res = (result.success? ? "success" : "failure")
    if GitHub.enterprise?
      auth_failure_key = result.success? ? "" : ".#{result.failure_reason || result.failure_type}"
      GitHub.stats.increment "auth.result.#{res}#{auth_failure_key}.#{from}"
    end

    tags = [
      "result:#{res}",
      "from:#{from}",
      "email_address_attempt:#{login&.to_s&.include?("@")}",
      "failure_type:#{result.failure_type}",
      "failure_reason:#{result.failure_reason}",
      "device_verification_method:#{result.sign_in_verification_method}",
    ]

    if token_attempt? && token_present?
      tags += [
        "token_type:#{token_type}",
        "new_token_format:#{result.new_token_format?}",
        "token_checksum_result:#{valid_checksum_result}",
      ]
      # Audit Log Token Information Addition
      # At this we have access to meaningful token information
      # DO NOT REMOVE
      Audit.context.push({
        hashed_token: hashed_token,
        token_type: token_type.to_s,
        programmatic_access_type: programmatic_access_type,
      })
    end

    GitHub.dogstats.increment("authentication.#{attempt_type}", tags: tags)
  end

  # Private: Log the authentication event
  #
  # Returns nothing.
  def log
    state     = result.success? ? "success" : "failure"
    raw_login = (login == token || AccessTokens.get_token_type(login) != :unknown) ? "TOKEN" : login
    # sanitize failure reason and type so that we won't leak sensative information in syslog, splunk
    failure_reason = result.failure_reason == :weak_password ? :password : result.failure_reason
    failure_type = result.failure_type == :weak_password ? :password : result.failure_type
    options = if token_attempt?
      token_attempt_context
    else
      {}
    end

    GitHub::Authentication.logger.info({
      "code.namespace" => self.class.name,
      "gh.auth.result.message" => result.message,
      "gh.auth.password_attempt" => password_attempt?,
      "gh.auth.token_attempt" => token_attempt?,
      "gh.auth.auth_attempt_data" => metadata,
      "code.function" => __method__,
      "gh.auth.result" => state,
      "gh.auth.origin" => from,
      "gh.auth.login" => attempted_user_login,
      "gh.auth.raw_login" => raw_login,
      "gh.enduser.id" => attempted_user_id,
      "gh.auth.failure.type" => failure_type,
      "gh.auth.failure.reason" => failure_reason,
      "gh.auth.result.two_factor_type" => result.two_factor_type,
      "gh.auth.result.sign_in_verification_method" => result.sign_in_verification_method,
      "gh.auth.result.sign_in_method" => result.sign_in_method,
    }.merge(options))
  end

  def token_attempt_context
    options = {
      "gh.auth.hashed_token" => hashed_token,
      "gh.auth.token_type" => token_type,
      "gh.auth.programmatic_access_type" => programmatic_access_type,
      "gh.auth.token_checksum_result" => valid_checksum_result,
      "gh.auth.token_length" => token&.length
    }

    if result.success?
      token_id = case token_type
      when :oauth_access
        result.user.oauth_access.id
      when :authentication_token
        # pushed into the context during lib/github/authentication/token_lookup.rb
        Audit.context[:token_id]
      when :user_programmatic_access
        result.user.programmatic_access.id
      end

      options["gh.auth.token_id"] = token_id
    end

    options
  end

  def from?(client)
    from.to_s == client.to_s
  end

  # Private: Add authentication event to the GitHub audit log.
  #
  # Returns nothing.
  def audit
    User.instrument_failed_login(
      actor_ip: metadata[:ip],
      note: "From #{from.to_s.humanize}",
      user: attempted_user_login,
      user_id: attempted_user_id,
      actor: attempted_user_login,
      actor_id: attempted_user_id,
      org_id: attempted_user_organization_ids,
      failure_reason: result.failure_reason,
      failure_type: result.failure_type,
      sign_in_method: result.sign_in_method,
    )
  end

  def memcache
    @memcache ||= GitHub.cache
  end

  # For now, we will only track web login events for users with the feature
  # enabled. In the future, we will track basic auth, API calls, etc.
  # two_factor_partial_sign_in? represents a partial sign in with a correct password and
  # not e.g. an incorrect TOTP code.
  def authentication_record_for_sign_in?
    octolytics_id &&
      from?(:web) &&
      result.two_factor_partial_sign_in? &&
      result.user.sign_in_analysis_enabled?
  end

  # Private: Should we enforce verified devices on this event?
  #
  # returns true for web sign ins where the feature is enabled and not opted out.
  def verified_device_required?(password_result)
    from?(:web) &&
      password_result.success? &&
      password_result.user.user? &&
      password_result.user.sign_in_analysis_enabled?
  end

  def attempt_stats_tag
    case from.to_s
    when "web"
      "sign_in"
    when "sudo"
      "sudo_challenge"
    when "git", "api", "web_api", "api_middleware", "lfs", "internal_lfs", "internal_api"
      from.to_s
    else
      from.to_s.presence || "other"
    end
  end
end
