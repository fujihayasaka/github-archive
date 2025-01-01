# typed: true
# frozen_string_literal: true

class ApplicationController
  module AuthenticatedSystem
    extend ActiveSupport::Concern

    extend T::Helpers
    requires_ancestor { ApplicationController }

    extend AbstractController::Helpers::ClassMethods
    extend ActiveSupport::Concern

    include GH::Auth::IdentityContext

    included do
      helper_method :current_device_id
      send :helper_method, :current_user, :logged_in?, :user_session,
        :webauthn_register_request,
        :security_key_webauthn_sign_request,
        :webauthn_sign_challenge_for_response,
        :trusted_device_webauthn_sign_request,
        :conditional_mediation_sign_request,
        :webauthn_sign_request
    end

    sig { override.returns(T.nilable(GH::Auth::Actor)) }
    def domain_actor
      current_user
    end

    protected

    def reject_fake_logins
      logged_in_cookie = request.cookies["logged_in"]
      return unless logged_in_cookie == "yes"

      if !current_user
        GitHub.dogstats.increment("rejected_fake_login", tags: dogstats_request_tags)

        request.cookies.delete("logged_in")
        redirect_to_login(request.url)
      end
    end

    def login_required_with_forced_redirect
      if !current_user
        redirect_to_login(request.url)
        return # rubocop:disable Style/RedundantReturn
      end
    end

    # Returns true or false if the user is logged in.
    # Preloads @current_user with the user model if they're logged in.
    def logged_in?
      !!current_user
    end

    # Allow subclass to add additional authentication methods.
    #
    # Returns User or nil.
    def authentication_methods
      login_from_user_session || nil
    end

    # Accesses the current user from the session.
    def current_user
      return @current_user if defined? @current_user

      # counts the number of times the current user is _actually_ loaded
      GitHub.dogstats.increment("experiment.current_user", tags: ["loaded:eager", "api:false"])

      self.current_user = authentication_methods
    end

    # Internal: Assign current_user for the duration of the request.
    #
    # Doesn't create any persisent sessions.
    #
    # user - The User
    #
    # Returns user.
    def current_user=(user)
      if user
        actor_context = user.event_context(prefix: :actor)
        GitHub.context.push(actor_context)
        Audit.context.push(actor_context)
      end

      if user_session
        GitHub.context.push(actor_session: user_session.id)
        Audit.context.push(actor_session: user_session.id)
        # if the current user session is impersonated, add extra audit log context
        # to be used later when displaying actions taken on the user's behalf
        if user_session.impersonated?
          impersonation_metadata = { session_impersonated: true, user: user.login, user_id: user.id } # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
          if GitHub.enterprise?
            impersonation_metadata[:session_impersonated_by] = user_session.impersonator_session.user
          end
          Audit.context.push(impersonation_metadata)
        end
      end

      @current_user = user
    end

    # The user who is either partially or fully authenticated. This is useful
    # for two-factor code.
    #
    # Returns a user or nil.
    def authentication_user
      return @authentication_user if defined? @authentication_user
      @authentication_user = current_user
    end

    # Check if the user is authorized
    #
    # Override this method in your controllers if you want to restrict access
    # to only a few actions or if you want to check if the user
    # has the correct rights.
    #
    # Example:
    #
    #  # only allow nonbobs
    #  def authorized?
    #    current_user.login != "bob"
    #  end
    def authorized?
      logged_in?
    end

    # Filter method to enforce a login requirement.
    #
    # To require logins for all actions, use this in your controllers:
    #
    #   before_action :login_required
    #
    # To require logins for specific actions, use this in your controllers:
    #
    #   before_action :login_required, :only => [ :edit, :update ]
    #
    # To skip this in a subclassed controller:
    #
    #   skip_before_action :login_required
    def login_required
      logged_in? || access_denied
    end

    # Filter method to enforce an anonymous user.
    def anon_required
      redirect_to "/" if logged_in?
    end

    # Filter method to enforce authorization.
    #
    # NOTE: There is a distinct difference between this and enforcing login.
    # The authorized? method is overridden in AbstractRepositoryController to
    # return true when in a public repository.
    def authorization_required
      authorized? || access_denied
    end

    # Redirect as appropriate when an access request fails.
    #
    # The default action is to redirect to the login screen.
    #
    # Override this method in your controllers if you want to have special
    # behavior in case the user is not authorized
    # to access the requested action.  For example, a popup window might
    # simply close itself.
    def access_denied
      if logged_in?
        render_404
      else
        respond_to do |format|
          format.html do
            if request.xhr?
              head :unauthorized
            else
              redirect_to_login(request.url)
            end
          end

          format.html_fragment do
            head :not_found
          end

          format.atom do
            set_header_for_no_index_and_no_follow
            head :unauthorized
          end

          format.json do
            headers["WWW-Authenticate"] = %(Basic realm="GitHub")
            render json: { error: "Couldn’t authenticate you" }, status: :not_found
          end

          format.all do
            headers["WWW-Authenticate"] = %(Basic realm="GitHub")
            render plain: "Couldn’t authenticate you", status: :not_found
          end
        end
      end

      false
    end

    # Override to opt an endpoint out of being able to touch/bump an active
    # session, thus extending its life. We have general restrictions on what
    # can bump a session, but sometimes we need to exclude specific endpoints.
    def allow_session_touching?
      true
    end

    # Store the URI of the current request in the session.
    #
    # We can return to this location by calling #redirect_to_return_to.
    def store_location
      session[:return_to] = request.fullpath
    end

    def permission_denied_if_mismatched_login_and_token
      access_denied if token_based_request? && !logged_in?
    end

    # login by authenticating from credentials found in the HTTP Authorization
    # header.
    def login_from_authorization_header_auth
      creds = Api::RequestCredentials.from_env(
        request.env,
        headers: true,
        params: false,
      )
      return unless creds.credentials_present?

      attempt = GitHub::Authentication::Attempt.new(
        from:       :web_api,
        login:      creds.login, # rubocop:disable GitHub/DoNotAllowLogin creds is not a user object
        password:   creds.password,
        otp:        creds.otp,
        token:      creds.token,
        ip:         request.remote_ip,
        user_agent: request.user_agent,
        request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
        url:        Rack::RequestLogger.url_for_logging(request.url),
      )

      if attempt.result.success?
        @authorization_header_authed = true
        attempt.result.user
      elsif attempt.result.web_api_with_password_failure?
        GitHub.dogstats.increment("api.authentication", tags: ["reason:web-api-password-deprecation"])
        pat_creation_url = settings_user_tokens_url(host: GitHub.host_name)
        respond_to do |format|
          format.all do
            headers["WWW-Authenticate"] = %(Basic realm="GitHub")
            render plain: "Deprecated authentication method. Create a Personal Access Token to access: #{pat_creation_url}", status: :unauthorized
          end
        end
        # we put a nil so that when this method is called in e.g. tree controller, it won't go into the
        # block where user.using_oauth_application? would cause a no method error for unsuccessfuly web_api auth.
        nil
      end
    end

    # Public
    def login_from_signed_auth_token(scope)
      return unless token_based_request? && scope.present?
      user = User.authenticate_with_signed_auth_token(
        token: params[:token],
        scope: scope,
      )
      @signed_token_authed = !user.nil?
      user
    end

    # Does this type of request support token authentication and is the user
    # attempting to authenticate using a token?
    #
    # Returns boolean.
    def token_based_request?
      params[:token] && token_request_format?
    end

    # Does this type of request support token authentication?
    #
    # Returns false unless overridden by the controller.
    def token_request_format?
      false
    end

    def authorization_header_authed?
      !!@authorization_header_authed
    end

    def signed_token_authed?
      !!@signed_token_authed
    end

    # Returns number of milliseconds
    def webauthn_timeout
      60.seconds.in_milliseconds
    end

    # How long an unused webauthn challenge is valid for
    def webauthn_challenge_timeout
      10.minutes
    end

    def webauthn_challenge_replay_key(user, challenge)
      "user.webauthn_request.consumed_challenge.#{user.id}_#{challenge}"
    end

    # CredentialCreationOptions for public key
    def webauthn_register_request(store: true, user: current_user, webauthn_reason:, convert_for: nil)
      case webauthn_reason
      when :security_key_registration
        register_passkey = false
      when :trusted_device_registration,
           :trusted_device_conversion
        register_passkey = user.passkeys_enabled?
      else
        # This means that our source code is inconsistent.
        raise "Invalid webauthn sign request reason"
      end

      # ECDSA_w_SHA256 is required for using FIDO U2F keys (including
      # CTAP2 authenticators):
      #
      # - https://www.w3.org/TR/webauthn/#fido-u2f-attestation
      # - https://www.w3.org/TR/webauthn/#signature-attestation-types
      #
      # RSASSA_PKCS1_v1_5 is required for Windows Hello:
      # https://docs.microsoft.com/en-us/microsoft-edge/dev-guide/windows-integration/web-authentication
      #
      # Note: the order of algs is significant.
      cose_algs = [
        -7, # ECDSA_w_SHA256
        -257, # RSASSA_PKCS1_v1_5
      ]

      # TODO(https://github.com/github/github/issues/113003): Can we use a
      # more specific name than "GitHub Enterprise"?
      rpName = GitHub.enterprise? ? "GitHub Enterprise" : "GitHub"
      rp = {
        name: rpName
      }
      rp[:id] = GitHub.webauthn_rp_id unless GitHub.webauthn_rp_id.nil?

      handle_record = WebauthnUserHandle.find_by(user_id: user.id)
      webauthn_user_handle = if handle_record.nil?
        WebauthnUserHandle.generate_value
      else
        handle_record.webauthn_user_handle
      end
      session[:webauthn_user_handle] = Base64.strict_encode64(webauthn_user_handle)

      authenticator_selection = if register_passkey
        {
          userVerification: :required,
          residentKey: :required,
        }
      # passkey ff users have a cross-platform restriction for security key registrations
      elsif user.passkeys_enabled?
        {
          userVerification: :preferred,
          residentKey: :discouraged,
          authenticator_attachment: "cross-platform",
        }
      # security key registrations before passkeys
      else
        {
          userVerification: :discouraged,
          residentKey: :discouraged,
        }
      end

      # when a user is upgrading a specific security key credential
      # set attachment to cross-platform if the cred is cross platform, otherwise leave unspecified so as to not block QR code flow
      authenticator_selection[:authenticator_attachment] = "cross-platform" if convert_for && !convert_for.platform_authenticator?

      exclude_registrations = if user.passkeys_enabled?
        user.u2f_registrations
      else
        user.u2f_registrations.security_keys
      end

      exclude_registrations -= [convert_for] if convert_for
      exclude_credentials = exclude_registrations.map(&:public_key_credential_descriptor)

      extensions = {
        credProps: true
      }
      extensions[:appidExclude] = GitHub.u2f_app_id unless GitHub.u2f_app_id.nil?

      {
        publicKey: {
          rp: rp,
          user: {
            id: Base64.strict_encode64(webauthn_user_handle),
            name: user.login, # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1311
            displayName: user.safe_profile_name,
          },
          pubKeyCredParams: cose_algs.map { |alg| { type: "public-key", alg: alg } },
          attestation: "none",
          timeout: webauthn_timeout,
          excludeCredentials: exclude_credentials,
          challenge: webauthn_register_challenge_for_response,
          authenticatorSelection: authenticator_selection,
          extensions: extensions,
        },
      }
    end

    # Generate a new signing challenge and store it in the session.
    # Signing challenge can't be reset per-request because of the two requests that we prep for login (normal + conditional mediation)
    #
    # Returns a challenge String.
    def webauthn_sign_challenge_for_response
      clear_expired_sign_challenge
      session[:sign_challenge_expires_at] ||= Time.now + webauthn_challenge_timeout
      session[:sign_challenge] ||= WebAuthn::Credential.options_for_get.challenge
    end

    # Retrieve the signing challenge from the session.
    #
    # Returns a challenge String.
    def webauthn_sign_challenge_from_request(user)
      expiration = session.delete(:sign_challenge_expires_at)
      return nil, :challenge_expired if expiration.nil? || expiration < Time.now
      challenge = session.delete(:sign_challenge)
      return nil, :challenge_missing if challenge.nil?
      guard_against_challenge_replay(user, challenge)
    end

    # Generate a new registration challenge and store it in the session.
    #
    # Returns a challenge String.
    def webauthn_register_challenge_for_response
      session[:webauthn_register_challenge_expires_at] = Time.now + webauthn_challenge_timeout
      session[:webauthn_register_challenge] = WebAuthn::Credential.options_for_get.challenge
    end

    # Retrieve the registration challenge from the session.
    #
    # Returns a challenge String.
    def webauthn_register_challenge_from_request(user)
      expiration = session.delete(:webauthn_register_challenge_expires_at)
      return nil, :challenge_expired if expiration.nil? || expiration < Time.now
      challenge = session.delete(:webauthn_register_challenge)
      return nil, :challenge_missing if challenge.nil?
      guard_against_challenge_replay(user, challenge)
    end

    # Once we're consuming a webauthn request and verifying the challenge, check KV to defend against replay
    def guard_against_challenge_replay(user, challenge)
      replay = GitHub::Authentication::KV.store.get(webauthn_challenge_replay_key(user, challenge)).value!
      # if we already seen this challenge then this is a replay scenario & the challenge is invalid
      return nil, :challenge_replay if replay.present?

      # otherwise save this challenge in KV to guard against future replay risk until it expires
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub::Authentication::KV.store.set(webauthn_challenge_replay_key(user, challenge), "true", expires: webauthn_challenge_timeout.from_now)
      end
      [challenge, nil]
    end

    def clear_expired_sign_challenge
      # clear stale challenge if expired
      return unless session[:sign_challenge_expires_at].present? && session[:sign_challenge_expires_at] < Time.now
      session.delete(:sign_challenge_expires_at)
      session.delete(:sign_challenge)
    end

    def current_device_id
      return unless GitHub.sign_in_analysis_enabled?
      return if serving_gist_standalone?

      return @current_device_id if defined?(@current_device_id)
      @current_device_id = begin
        if cookies[:_device_id] && cookies[:_device_id] !~ AuthenticatedDevice::DEVICE_ID_REGEX
          GitHub.dogstats.increment("authenticated_device", tags: ["action:access", "error:malformed_device_id"])
          cookies.delete(:_device_id)
        end

        cookies[:_device_id] ||= begin
          GitHub.dogstats.increment("authenticated_devices.cookie", tags: [
            "controller:#{params[:controller]}",
            "action:#{params[:action]}",
          ])

          {
            value: AuthenticatedDevice.generate_id,
            expires: 1.year.from_now,
          }
        end

        cookies[:_device_id]
      end
    end

    # Updates access_at for the authenticated_device record and refreshes the device_id cookie
    #
    # Returns true when updates occur
    def touch_authenticated_device(authenticated_device)
      return unless GitHub.sign_in_analysis_enabled? && authenticated_device
      return if serving_gist_standalone?
      return unless authenticated_device.throttled_touch

      # bump the browser cookie expiration when we touch the authenticated_devices record
      cookies[:_device_id] = {
        value: @current_device_id,
        expires: 1.year.from_now,
      }

      true
    end

    def webauthn_sign_request(user: current_user, webauthn_reason:)
      case webauthn_reason
      when :two_factor_sign_in,
           :two_factor_sudo,
           :password_reset,
           # Note: we need to include security keys for the re-association prompt
           # in case the user currently has their platform authenticator registered
           # as a security key. This allows us to fall back to the conversion flow
           # instead of showing a confusing error.
           :passkey_promote_confirmation
        security_key_webauthn_sign_request(user: user, promote_confirm: webauthn_reason == :passkey_promote_confirmation)
      when :passwordless_sign_in
        trusted_device_webauthn_sign_request(user: user)
      else
        # This means that our source code is inconsistent.
        raise "Invalid webauthn sign request reason"
      end
    end

    def security_key_webauthn_sign_request(user: current_user, promote_confirm: false)
      security_keys = user.u2f_registrations.security_keys
      trusted_devices = user.u2f_registrations.passkeys
      allow_credentials = security_keys + trusted_devices
      no_legacy_keys = user.u2f_registrations.where(is_webauthn_registration: false).empty?

      extensions = {}
      extensions[:appid] = GitHub.u2f_app_id unless GitHub.u2f_app_id.nil? || no_legacy_keys

      publicKey = {
        userVerification: promote_confirm ? "required" : "discouraged",
        timeout: webauthn_timeout,
        challenge: webauthn_sign_challenge_for_response,
        allowCredentials: allow_credentials.map(&:public_key_credential_descriptor),
        extensions: extensions,
      }
      publicKey[:rpId] = GitHub.webauthn_rp_id unless GitHub.webauthn_rp_id.nil?

      { publicKey: publicKey }
    end

    def trusted_device_webauthn_sign_request(user: current_user)
      publicKey = {
        userVerification: "required",
        timeout: webauthn_timeout,
        challenge: webauthn_sign_challenge_for_response,
        allowCredentials: user ? user.u2f_registrations.passkeys.map(&:public_key_credential_descriptor) : [],
      }
      publicKey[:rpId] = GitHub.webauthn_rp_id unless GitHub.webauthn_rp_id.nil?

      { publicKey: publicKey }
    end

    def conditional_mediation_sign_request
      publicKey = {
        userVerification: "required",
        timeout: webauthn_timeout,
        challenge: webauthn_sign_challenge_for_response,
        allowCredentials: [],
      }
      publicKey[:rpId] = GitHub.webauthn_rp_id unless GitHub.webauthn_rp_id.nil?

      { publicKey: publicKey, mediation: "conditional" }
    end

    private

    HTTP_AUTH_HEADERS = %w(X-HTTP_AUTHORIZATION HTTP_AUTHORIZATION Authorization)
    def http_authentication_header
      auth_key = HTTP_AUTH_HEADERS.detect { |h| request.env.has_key?(h) }
      auth_key.present? && request.env[auth_key].to_s[/^Basic\s+(.*)/m, 1]
    end
  end
end
