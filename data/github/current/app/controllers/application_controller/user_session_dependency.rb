# typed: true
# frozen_string_literal: true

# User Session controller concern
#
# See Also
#
#   UserSession model - app/models/user_session.rb
#
module ApplicationController::UserSessionDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include FeatureFlagHelper
  include SetLoggedOutCookieConcern

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, AbstractController::Helpers::ClassMethods)
    helper_method :serving_gist_standalone?
    helper_method :user_session
    helper_method :session_impersonated?
  end

  # Our SameSite cookies make use of the cookie prefixes spec. As a result,
  # these cookie names have awkward prefixes. So, we define constants to make
  # using them less awkward to reference in code.
  USER_SESSION_COOKIE_SAME_SITE = :"__Host-user_session_same_site"
  GIST_USER_SESSION_COOKIE_SAME_SITE = :"__Host-gist_user_session_same_site"

  protected

  # Public: Provides `authentication_methods` hook for authenticating via
  # user_session.
  #
  # Returns User or nil.
  def login_from_user_session
    if user_session
      user_session.user
    end
  end

  # Are we serving a Gist3 Standalone request?
  # aka gist3.github.com or gist3.github.dev
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def serving_gist_standalone?
    @serving_gist3 ||= if GitHub.gist3_domain?
      request.host == GitHub.gist3_host_name
    else
      false
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Overrides default user_session method to lookup
  # the session using the gist specific session cookie and stored hashed key value.
  # The cookie and hashed keys are initially written during the Oauth callback.
  def user_session
    if serving_gist_standalone?
      gist_user_session
    else
      dotcom_user_session
    end
  end

  # Public: Lookup session record for authenticated user by their
  # `user_session` cookie.
  #
  # Returns a UserSession model or nil.
  def dotcom_user_session
    return @user_session if defined? @user_session

    GitHub.tracer.in_span("dotcom_user_session", attributes: {
      "gh.request_id" => env["HTTP_X_GITHUB_REQUEST_ID"].to_s,
      "gh.user.connection.role" => User.connection_pool.role.to_s
    }, kind: :internal) do |span|
      if stateless_request? || !UserSession.valid_key_format?(cookies[:user_session])
        @user_session = nil
      elsif result = UserSession.authenticate(cookies[:user_session])
        check_current_user_presence(span)

        # @user_session_key is set at the controller scope here for explicit use by the touch_user_session before action method
        @user_session, @user_session_key = result
        @same_site_cookie_request = @user_session &&
          SecurityUtils.secure_compare(
            cookies[:user_session].to_s,
            cookies[USER_SESSION_COOKIE_SAME_SITE].to_s,
          )

        if GitHub.subdomain_private_mode_enabled?
          # Auth and retouch the private mode session if necessary
          touch_authenticated_private_mode_user_session @user_session
        end

        assess_cookie_drift
        GitHub.dogstats.increment("user_session.hydrate", tags: ["in_use:#{@user_session.in_use}"])
      else
        @user_session_lookup_failed_at ||= Time.now.utc
      end
    end

    @user_session
  end

  def gist_user_session
    return @user_session if defined? @user_session

    if result = UserSession.authenticate(cookies[:gist_user_session], hashed_key_column: :hashed_gist_key)
      # @user_session_key is set at the controller scope here for explicit use by the touch_user_session before action method
      @user_session, @user_session_key = result

      # ignore the `gist_user_session` if it is not in use.  this indicates the user is logged into a
      # different account on Dotcom (e.g. by switching or adding accounts).  ignoring the session here will cause
      # gist to redo the oauth flow to sync up their cookies.
      if account_switcher_helper.enabled? && !@user_session.in_use?
        GitHub.dogstats.increment("account_switcher.gist_session_not_in_use", tags: ["in_use:#{@user_session.in_use}"])
        user_session_cookies_delete
        @user_session, @user_session_key = nil, nil
        return
      end

      @same_site_cookie_request = @user_session &&
        SecurityUtils.secure_compare(
          cookies[:gist_user_session].to_s,
          cookies[GIST_USER_SESSION_COOKIE_SAME_SITE].to_s,
        )

      @user_session
    else
      @user_session = nil
    end
  end

  def user_session_cookies_delete
    if serving_gist_standalone?
      cookies.delete(:gist_user_session)
      cookies.delete(
        GIST_USER_SESSION_COOKIE_SAME_SITE,
        secure: true,
        domain: nil,
      ) if GitHub.same_site_cookie_enabled?
    else
      user_session_key = cookies.delete(:user_session)
      cookies.delete(
        USER_SESSION_COOKIE_SAME_SITE,
        secure: true,
        domain: nil,
      ) if GitHub.same_site_cookie_enabled?
    end
  end

  # Public: Checks if, during user session lookup, a matching strict SameSite
  # session cookie was submitted along with the normal user session cookie. If
  # a browser doesn't support SameSite cookies it will always submit the
  # strict SameSite cookie, allowing us to be backward compatible. If a
  # browser does support SameSite cookies, we can use the presence/absence of
  # the strict SameSite cookie to determine if this was a same origin request
  # or not (useful for additional CSRF validation).
  #
  # Returns true if this request included our strict SameSite cookie and
  # false otherwise.
  def same_site_cookie_request?
    return true unless GitHub.same_site_cookie_verification_enabled?
    # SameSite cookies are not used for anonymous cookie based sessions.
    return true unless user_session
    !!@same_site_cookie_request
  end

  # Public: Checks if current session is actually a staff user impersonating
  # someone elses session.
  #
  # Returns true or false.
  def session_impersonated?
    user_session && user_session.impersonated?
  end

  # Public: Login user.
  #
  # Either creates a new session record for fresh sign in or switches to an
  # existing session for account switching.  In both cases, sets the user_session
  # cookie as well as any legacy session cookies. current_user is updated to reflect the user.
  #
  # user - The User
  # sign_in_verification_method: required, reason this sign in is allowed
  #   (can be nil for for password change events)
  # client: the source of the login_user event. This is also called when a
  #   user changes their password or impersonates another user
  # authenticated_device: optional, the device used during sign in or nil
  # existing_session: optional, the valid user session for the account that
  #   the user is switching to.
  # existing_session_key: optional, the secret key corresponding to existing_session.
  # payload: optional, additional data to log with the login audit log / hydro event
  #
  # Returns user.
  def login_user(user,
    sign_in_verification_method:,
    authenticated_device: nil,
    client: :web,
    existing_session: nil,
    existing_session_key: nil,
    payload: {}
  )
    if payload && payload[:social_accrual_confirm]
      social_info = payload[:social_accrual_confirm]
      if social_info["expires_at"].present? && social_info["expires_at"].to_time.past?
        flash[:error] = "Your social linkage request has expired. Please try again."
      else
        begin
          response = SocialIdentities.domain.register_social_identity(social_info["provider_id"], social_info["subject"], social_info["user_id"], social_info["email_id"], social_info["email"])
          GitHub.dogstats.increment("authentication.social_accrual", tags: ["result:#{response.result}", "vscode:#{vscode_return_to}"])
          if response.result == :RESULT_SUCCESS
            AccountMailer.social_identity_added(social_info["provider"], UserEmail.find_by(email: social_info["email"])).deliver_later
            flash[:notice] = "Your social identity has been successfully linked to #{user.display_login}."
          else
            msg = "We could not validate the response from your social login provider. Please try again or use our alternative sign-in or sign-up options."
            flash[:error] = msg
          end
        rescue ::Authnd::Proto::Error, Faraday::Error => err
          flash[:error] = "We could not validate the response from your social login provider. Please try again or use our alternative sign-in or sign-up options."
        end
      end
    end

    authenticated_device = T.let(authenticated_device, T.nilable(AuthenticatedDevice))

    tags = ["client:#{client}", "sign_in_verification_method:#{sign_in_verification_method}"]
    tags << "switching_accounts:true" if existing_session
    GitHub.dogstats.distribution_time("login_user.dist.duration", tags: tags) do
      raise TypeError, "can't login nil user" unless user
      log_data[:user] = user.login # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs

      if user.sign_in_analysis_enabled?
        authenticated_device ||= user.authenticated_devices.find_by_device_id(current_device_id)
        verify_user_device(authenticated_device) if sign_in_verification_method
      end

      # Always reset the cookie store session when logging in a user or switching accounts
      persistent_reset_session

      if user_session
        # mark the current user_sesson as not in use before switching/adding accounts
        user_session.in_use = false
        user_session.save
      end

      if existing_session
        if !SecurityUtils.secure_compare(UserSession.hash_key(existing_session_key), existing_session.hashed_key)
          GitHub.dogstats.increment("existing_session_key_mismatch", tags: tags)
          raise ArgumentError, "existing_session_key does not match existing_session"
        end

        log_switch_accounts(user_session, existing_session) if user_session && !client == :password_changed

        # mark the new user_sesson we're switching to as "in use"
        @user_session, key = existing_session, existing_session_key
        @user_session.in_use = true
        @user_session.save

        # tell front-end to clear local storage
        set_logged_out_cookie
      else
        # If theres already a session kill it before we switch as long as they can't use
        # the AccountSwitcher feature to add a user. The old session would be lost to the aether otherwise.
        if user_session && !account_switcher_helper.enabled?(additional_user_check: user)
          user_session.revoke(:legacy_switched_users)
        end

        # Generate new key pair for new session
        key, hashed_key = UserSession.create_user_session_key_pair(user)
        private_mode_key, hashed_private_mode_key = UserSession.random_key_pair
        @user_session = user.sessions.build(
          hashed_key: hashed_key,
          hashed_private_mode_key: hashed_private_mode_key,
        )

        # ensure device-tracking values are set as cookie objects
        @user_session.assign_attributes_from_request(request)
        # mark the new user_sesson we're switching to as "in use"
        @user_session.in_use = true
        @user_session.save!
      end
      log_data[:user_session_id] = @user_session.id

      # enqueue job to prune older sessions when over the limit
      EnforceActiveUserSessionLimitJob.perform_later(user) if user.enforce_active_session_limit?

      # If the AccountSwitcher is available and we're not switching accounts, we need to store the key for the
      # newly created session for `user` and the old session belonging to `current_user`.
      # This allows those sessions to be referenced switching accounts as long as they're
      # valid and present in the `saved_user_sessions` cookie.
      if account_switcher_helper.enabled?(additional_user_check: user) && !existing_session
        current_sessions_hash = {}
        current_sessions_hash[user.id] = key
        current_sessions_hash[current_user.id] = cookies[:user_session].presence if current_user
        update_saved_user_session_cookie(current_sessions_hash)
      end

      # Set user_session cookie for the newly created or swapped to session
      set_session_cookie(@user_session, key)

      # Re-set cookies so secure_headers will "Upgrade" cookies set by client to pick up samesite attribute
      cookies[:tz] = cookies.delete(:tz)

      if GitHub.subdomain_private_mode_enabled?
        touch_subdomain_private_mode_user_session(@user_session, private_mode_key)
      end

      self.current_user = user
      authentication_record = establish_history(user, @user_session, authenticated_device, client)

      if !existing_session && client != :password_changed
        log_login(sign_in_verification_method, authentication_record, payload: payload)
      end

      user.set_low_two_factor_method_banner(:login) if user.show_low_two_factor_method_banner?
    end

    session[:recent_login] = true unless existing_session
    self.current_user
  end

  def social_session_payload
    payload = {
      sign_in_method: session[:sign_in_method],
      social_email_id: session[:social_email_id],
      social_email_address: session[:social_email_address]
    }

    # if session[:social_accrual_confirm] exists, add that to the payload
    if session[:social_accrual_confirm]
      payload[:social_accrual_confirm] = session[:social_accrual_confirm]
    end

    payload
  end

  def accountless_signup_device(user, authenticated_device)
    verify_user_device(authenticated_device)
    establish_history(user, nil, authenticated_device, :sign_up)
  end

  # Internal: create an authentication record for this event
  #
  # Returns the record that was created or nil
  def establish_history(user, user_session, authenticated_device, client)
    GitHub.dogstats.distribution_time("establish_history.dist.duration", tags: ["client:#{client}"]) do
      return unless user.sign_in_analysis_enabled?
      return if user_session&.impersonated?
      return unless cookies[:_octo] # sign ins will always have this value

      case client
      when :two_factor_partial_sign_in
        # 2FA sign ins can technically not be associated to a device if the user
        # mucks with the cookies between requests.
        return unless authenticated_device
      end

      history_exists = client == :user_session && user_session.present? && ActiveRecord::Base.connected_to(role: :reading) do
        user_session.authentication_records.where(ip_address: request.remote_ip).exists?
      end

      return unless !history_exists && !AuthenticationRecord.user_rate_limited?(user)

      tags = [
        "action:establish_history",
        "client:#{client}",
        "authenticated_device_present:#{!!authenticated_device}",
      ]

      begin
        ActiveRecord::Base.connected_to(role: :writing) do
          AuthenticationRecord.create!(
            user: user,
            octolytics_id: current_visitor.octolytics_id,
            client: client,
            user_agent: user_session&.user_agent || request.user_agent,
            user_session: user_session,
            authenticated_device: authenticated_device,
            ip_address: request.remote_ip,
            location: user_session&.location || GitHub::Location.look_up(request.remote_ip),
          )
        end.tap do |authentication_record|
          if client == :web
            tags << "authentication_record_persisted:#{authentication_record&.persisted?}"
          end
          GitHub.dogstats.increment("user_session_auth_records", tags: tags)
        end
      rescue ActiveRecord::RecordInvalid => e
        GitHub.dogstats.increment("user_session_auth_records", tags:
          tags + ["error:#{e.class.name&.dasherize}"]
        )
        nil
      end
    end
  end

  # Public: Log out users associated with given user_session.
  #
  # Resets session, wipes any user_session cookie and revokes the session
  # state from the database. Sets current_user and @user_session to nil
  # if logging out the current user.
  #
  # reason - Why user is being logged out.
  #          See UserSession:VALID_REVOKE_REASONS for valid keys.
  # target_user_session - The UserSession to revoke. Defaults to the @user_session.
  #
  # Returns nothing.
  def logout_user(reason = :logout, target_user_session: user_session)
    # skip clearing user_session cookies if we're logging out an account other than current_user
    target_is_current_user = target_user_session == user_session
    if !logged_in? || target_is_current_user
      user_session_cookies_delete
    end

    if target_user_session
      sign_in_record = target_user_session.sign_in_record
      target_user_session.revoke(reason)

      GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
      GlobalInstrumenter.instrument "user.logout", {
        actor: target_user_session.user,
        known_device: sign_in_record&.known_device?,
        known_location: sign_in_record&.known_location?,
        request_time_left: request_time_left
      }

      if target_is_current_user
        @user_session = nil
        self.current_user = nil
      end
    end
  end

  # Public: Replaces the current user's session with an impersonated session
  # of the target user.
  #
  # user - The User
  #
  # Returns user.
  def impersonated_login_user(user, reason)
    # current user becomes the impersonator
    unless former_user_session = user_session
      raise ArgumentError, "no user to set as impersonator"
    end

    # Generate new key pair for impersonated session
    key, hashed_key = UserSession.random_key_pair
    @user_session = user.sessions.build(
      hashed_key: hashed_key,
      impersonator_session: former_user_session,
    )
    @user_session.assign_attributes_from_request(request)
    @user_session.save!

    # Set user session cookie since we created a new one
    set_session_cookie(@user_session, key)

    # Send the user an impersonation notification (email) if we are in enterprise mode
    if GitHub.enterprise?
      admin_login = current_user.display_login
      StaffAccessMailer.impersonation_notification(user, reason, admin_login).deliver_later
    end

    self.current_user = user
  end

  # Public: Restore original staff users session and kill impersonated
  # session.
  #
  # Returns former User.
  def impersonated_logout_user
    unless impersonated_user_session = user_session
      raise ArgumentError, "no impersonator user to log out"
    end

    unless former_user_session = impersonated_user_session.impersonator_session
      raise ArgumentError, "no former user to log back in"
    end

    impersonated_user_session.revoke(:unimpersonate)

    @user_session = former_user_session

    # Generate a new key pair for the users old session
    # Kinda weird, but we don't actually know their old unhashed key
    # anymore. Just generate a new one.
    key, hashed_key = UserSession.random_key_pair
    user_session.hashed_key = hashed_key
    user_session.save!

    # Touch user session to set new user_session cookie
    set_session_cookie(@user_session, key)

    self.current_user = former_user_session.user
  end

  # A basic heuristic that tries to answer "do we think this was a human
  # doing things on dotcom excluding AJAX." This includes same site,
  # browser_full/pjax. We also exclude some noisy requests
  # that make it through this filter by opting-out via @dont_touch_session
  def should_touch_session?
    # ensure the request category is set before consulting it. The session
    # itself will be memoized in case the order of operations changes.
    request_categorization_filter

    allow_session_touching? &&
      request.format.try(:html?) &&
      full_navigation_request_category? &&
      same_site_cookie_request?
  end

  def assess_cookie_drift
    # current_user hasn't beeen set yet
    return unless @user_session.user.feature_flag_enabled?(:session_cookie_analysis, default: false)
    # if user_session.accessed_at is already ahead of the date this change shipped (touch_user_session hasn't been called yet)
    # then we expect the gh_sess value to be present and we expect it to match the value on the current user_session

    log_info = {
      "gh.request_id" => env["HTTP_X_GITHUB_REQUEST_ID"],
      "gh.request.gh_sess.id" => session[:user_session_id],
      "gh.request.gh_sess.accessed_at" => session[:user_session_accessed_at],
      "gh.request.user_session.id" => @user_session.id,
      "gh.request.user_session.accessed_at" => @user_session.accessed_at,
      "gh.request.session_mismatch" => @user_session.id != session[:user_session_id],
      "gh.request.session_drift" => @user_session.accessed_at != session[:user_session_accessed_at],
    }

    GitHub.logger.info("assess_cookie_drift", log_info)
  end

  # Internal: Trusts the user's device. This is the first time in the
  # login flow that we can fully trust the user has been authenticated
  # and thus their device can now be trusted. We don't verify devices
  # for users that bypass verification due to bounced+unverified emails
  #
  # authenticated_device - the current device
  def verify_user_device(authenticated_device)
    return if session_impersonated?

    unless authenticated_device&.verify!
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:attempted_to_trust_nil_device_during_login"])
    end
  end

  def touch_user_session
    return if user_session.nil? || @user_session_key.nil? || !should_touch_session?

    touched_session = user_session.access(request)

    # for dotcom only, touch device history
    if touched_session && !serving_gist_standalone?
      touch_device_history(user_session)
    end

    if touched_session
      # If we touched the session without throttling, then touch the cookie too.
      if serving_gist_standalone?
        set_session_cookie(user_session, @user_session_key, cookie_name: :gist_user_session)
      else
        set_session_cookie(user_session, @user_session_key)
      end
    end

    # @user_session_key was explicitly set at the controller scope level for this before_action method.
    # here, we are setting this to nil so nothing else will depend on / use @user_session_key
    # also if this ends up being called more than once, we will only set the cookie once per request.
    @user_session_key = nil
  end

  def touch_device_history(user_session)
    raise TypeError, "can't touch device history for nil user session" unless user_session

    if current_user.sign_in_analysis_enabled?
      authenticated_device = current_user.authenticated_devices.find_by_device_id(current_device_id)

      establish_history(current_user, user_session, authenticated_device, :user_session)
      tags = ["action:touch", "from:user_session_dependency"]
      if authenticated_device
        touch_authenticated_device(authenticated_device)
      else
        tags << "error:unpersisted_device"
      end
      GitHub.dogstats.increment("authenticated_device", tags: tags)
    end
  end

  # Internal: Set initial session cookie or push current expiry out further
  #
  # user_session - The UserSession
  # key          - Unhashed key String
  # cookie_name  - The cookie to store the user session signed key (optional).
  #
  # Returns nothing.
  def set_session_cookie(user_session, key, cookie_name: :user_session)
    cookies[cookie_name] = {
      value: key,
      expires: user_session.expire_time,
    }

    if user_session.user.feature_flag_enabled?(:session_cookie_analysis, default: false)
      session[:user_session_id] = user_session.id
      session[:user_session_accessed_at] = user_session.accessed_at
    end

    if GitHub.same_site_cookie_enabled?
      cookies["__Host-#{cookie_name}_same_site"] = {
        value: key,
        expires: user_session.expire_time,
        same_site: "Strict"
      }
    end

    nil
  end

  # Public: Replaces the current user's user_session cookie key with a new one.
  # This is primarily used for SSO/SAML authentication to prevent stolen user_session cookies
  # allowing bad actors refreshed access to org/enterprise resources.
  #
  # user - The User
  #
  # Returns nothing.
  def rotate_user_session_key(reason)
    return if current_user.nil? || user_session.nil?
    return unless current_user.feature_flag_enabled?(:rotate_user_session_key, default: false)

    key, hashed_key = user_session.rotate_hashed_key(reason)
    set_session_cookie(user_session, key)

    if account_switcher_helper.enabled?(additional_user_check: current_user)
      current_sessions_hash = {}
      current_sessions_hash[current_user.id] = key
      update_saved_user_session_cookie(current_sessions_hash)
    end
  end

  # Logging a user in with `ApplicationController#login_user` resets the
  # cookie session. However, there are some values stored in the session that
  # we would like to persist after login.
  #
  # return_to                     - The location to redirect the user after the SAML SSO
  #                                 consume action. If this does not persist then features like testing
  #                                 organization SAML provider settings will not work and
  #                                 in some cases users will not be redirected to the
  #                                 correct location after authenticating via SAML SSO.
  # sso_invitation_token          - Represents an organization invitation ID in the
  #                                 database. If this does not persist then we end up with orphaned
  #                                 invitations after a user signs up via SAML SSO.
  # saml_user_data                - The SAML user data from a SAML assertion,
  #                                 used to provision a new user account without creating an
  #                                 unlinked external identity first.
  # unlinked_session_expires_at   - The DateTime value representing the
  #                                 expiry of the current user's external
  #                                 identity session. If this does not
  #                                 persist then the user will be required to
  #                                 constantly re-authenticate with SAML SSO.
  # saved_user_sessions           - Stores other user sessions that the user
  #                                 can switch to. If this does not persist
  #                                 then the user will never be able to add additional sessions.
  # copilot_auto_submit_prompt    - The logged-out Copilot chat experience allows entering a
  #                                 prompt which starts by redirecting to an authentication flow
  #                                 and ends by auto-submitting the entered prompt.
  PERSISTENT_COOKIE_SESSION_KEYS = [
    :return_to,
    :sso_invitation_token,
    :saml_user_data,
    :unlinked_session_expires_at,
    :trusted_device_supported,
    :saved_user_sessions,
    :copilot_auto_submit_prompt,
    ::CompromisedPassword::WEAK_PASSWORD_KEY,
    FlipperSession.session_key,
    :social_accrual_confirm
  ].freeze

  # Internal: reset the user's cookie session, but persists any keys/values in
  # the new session if they are whitelisetd in PERSISTENT_COOKIE_SESSION_KEYS.
  #
  # Returns the new session.
  def persistent_reset_session
    old_session = {}
    PERSISTENT_COOKIE_SESSION_KEYS.each do |key|
      old_session[key] = session[key]
    end

    reset_session

    old_session.each do |key, value|
      session[key] = value
    end

    session
  end

  def social_session_cleanup
    session.delete(:social_oidc_state)
    session.delete(:social_oidc_nonce)
    session.delete(:social_oidc_code_verifier)
  end

  def vscode_return_to
    session[:return_to]&.include?(Apps::Privileged::Codespaces::VSCODE_AUTH_SERVER_KEY)
  end

  # Track if we authenticate a user_session without a current_user
  #
  # This should not be happening anymore. If the first `logged_in?` call for a request runs behind a forced read-only
  # connection, we can incorrectly memoize the current_user as missing. We want to avoid a regression.
  def check_current_user_presence(span)
    if defined?(@user_session_lookup_failed_at) && current_user.nil?
      # user_session wasn't initially found on the first call, but has subsequently been found.

      # Note: we need to manually populate the request ID in the log/trace because it can be called prior to populating
      # the logger/tracer context for the request.
      GitHub.logger.info("current_user should not be nil", {
        "gh.request_id" => env["HTTP_X_GITHUB_REQUEST_ID"],
        "gh.user.connection.role" => User.connection_pool.role,
        "gh.session.time_since_hydration_failed" => (Time.now.utc - @user_session_lookup_failed_at).to_f,
      })
      GitHub.dogstats.increment("current_user.memoization_error")
      Failbot.report(RuntimeError.new("current_user should not be nil"))
      span.status = OpenTelemetry::Trace::Status.error("current_user should not be nil")
    end
  end

  if GitHub.allow_private_mode_user_session_cookie?
    # Internal: Touch the the current private_mode_user_session if its
    # authenticated.
    #
    # Should be invoked anytime the main user_session is touched to ensure the
    # subdomain cookie's expiry is pushed into the future as the user accesses
    # the site.
    #
    # user_session - The UserSession of the logged in user.
    #
    # Returns nothing.
    def touch_authenticated_private_mode_user_session(user_session)
      if result = UserSession.authenticate_private_mode(cookies[:private_mode_user_session])
        touch_subdomain_private_mode_user_session(*result)
      elsif user_session
        private_mode_key, hashed_private_mode_key = UserSession.random_key_pair
        user_session.hashed_private_mode_key = hashed_private_mode_key
        ActiveRecord::Base.connected_to(role: :writing) do
          user_session.save!
        end
        touch_subdomain_private_mode_user_session(user_session, private_mode_key)
      end
    end

    # Internal: Set subdomain wide private_mode_user_session cookie. Used on
    # Enterprise to authenticate all non-github.com requests via an nginx
    # authentication proxy.
    #
    # TODO: Link up where nginx is configured.
    def touch_subdomain_private_mode_user_session(user_session, key)
      raise TypeError, "can’t touch nil user session" unless user_session

      cookies[:private_mode_user_session] = {
        value: key,
        expires: user_session.expire_time,
        domain: cookie_domain,
      }

      nil
    end
  end
end
