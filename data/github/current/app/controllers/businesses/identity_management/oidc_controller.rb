# typed: true
# frozen_string_literal: true

require "date"
require "oidc"

class Businesses::IdentityManagement::OIDCController < Businesses::BusinessController
  include FeatureFlagHelper
  include SsoHelper
  include OIDCDependency
  include OIDC::CallbackValidator

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:recover_prompt]

  # How long does an admin's recovery session last?
  RECOVERY_SESSION_EXPIRY = 24.hours

  class AuthError < StandardError
    private_class_method :new

    attr_reader :at, :message, :errors, :sso_error, :login, :external_id

    def initialize(at, message, errors, sso_error, login: nil, external_id: nil)
      @at = at
      @message = message
      @errors = errors || []
      @sso_error = sso_error
      @login = login || "_unknown"
      @external_id = external_id || "_unknown"
    end

    def self.identity_not_found(external_id, user: nil)
      new(OIDC::CallbackValidator::UNAUTHORIZED_AT, OIDC::CallbackValidator::UNAUTHORIZED_MESSAGE, nil,
        :identity_not_found, login: user&.login, external_id: external_id) # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end

    def self.could_not_obtain_refresh_token(external_id, user: nil)
      new(OIDC::CallbackValidator::REFRESHTOKEN_AT, OIDC::CallbackValidator::REFRESHTOKEN_MESSAGE, nil,
        :invalid_idp_response, login: user&.login, external_id: external_id) # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end

    def self.user_not_singed_in(external_id, user: nil)
      new(OIDC::CallbackValidator::UNAUTHORIZED_AT, OIDC::CallbackValidator::UNAUTHORIZED_MESSAGE, nil,
        :user_not_singed_in, login: user&.login, external_id: external_id) # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end

    def self.error(result)
      new(result.at, result.error_message, nil, result.sso_error, login: result.login, external_id: result.external_id) # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end
  end

  # For first EMU admins login, we are now partially signing them in if they do not have 2FA
  # We require them to enter the recovery code to bypass SSO and to be fully logged in
  before_action :business_owner_required, unless: :first_emu_admin_partially_signed_in?, only: %w(recover_prompt recover)
  before_action :business_oidc_required, only: %w(initiate recover recover_prompt revoke)
  before_action :repost_response, if: :repost_response?, only: %w(callback)

  skip_before_action :verify_authenticity_token, only: [:callback]

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: :recover,
    if: :oidc_recover_rate_limit_filter,
    key: :oidc_recover_rate_limit_key,
    log_key: :oidc_recover_rate_limit_log_key,
    max: :oidc_recover_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    at_limit: :oidc_recover_rate_limit_record

  # The following actions do not need the EMU visibility policy.
  # We expect anon requests to be able to initiate SSO to login
  def emu_visibility_enforceable # rubocop:todo GitHub/UseRestfulActions
    return :no if %w(initiate callback).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    :yes
  end

  # The following actions do not need the multi-tenancy policy.
  # We expect anon requests to be able to initiate SSO to login
  private def tenant_verification_enforceable
    return :no if %w(initiate callback).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    :yes
  end

  # Override that determines whether an individual controller action should have
  # IP allow list enforcement applied.
  #
  # The following actions do not require IP allow list enforcement:
  #
  #   business's OIDC SSO configuration
  # - callback: serves `/oidc/callback`, consumes OIDC response, creating SSO sessions (when successful)
  #
  # Returns Symbol.
  private def ip_allowlist_enforceable
    return :no if %w(callback).include?(action_name)
    super
  end

  # Override that determines whether an individual controller action should have
  # conditional access policy enforcement applied.
  #
  # The following actions do not require conditional access policy enforcement:
  #
  #   business's OIDC SSO configuration
  # - callback: serves `/oidc/callback`, consumes OIDC response, creating SSO sessions (when successful)
  #
  # Returns Symbol.
  private def external_conditional_access_policy_enforceable
    # there is no this_business set at this point
    return :no if %w(initiate callback).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    super
  end

  # The following actions do not need the EMU ownership policy.
  # We expect logged in users to be able to switch to an emu account
  def emu_ownership_enforceable  # rubocop:todo GitHub/UseRestfulActions
    return :no if %w(callback).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    return :yes unless this_business&.sso_redirect_enabled?
    return :no if %w(initiate).include?(action_name)
    :yes
  end

  # Public: Stop conditional access check, since the call to SSO can be anonymous.  Only
  #   setup and authorization calls require a logged in user
  private def target_for_conditional_access
    return :no_target_for_conditional_access if %w(callback).include?(action_name) # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    super
  end

  # Override that determines whether an individual controller action should have
  # external identity session enforcement applied.
  #
  # The following actions do not require external identity session enforcement:
  #
  # - initiate: serves `/enterprises/:slug/oidc/initiate`, initiates SSO
  # - callback: serves `/oidc/callback`, consumes OIDC response, creating SSO sessions (when successful)
  # - recover_prompt: serves `GET /enterprises/:slug/oidc/recover`, allows admins to
  #   enter a recovery code to bypass SSO; POSTs to `/enterprises/:slug/oidc/recover`
  # - recover: serves `POST /enterprises/:slug/oidc/recover`, allows admins to submit
  #   a recovery code to bypass SSO
  #
  # Returns Boolean.
  private def require_active_external_identity_session?
    !%w(initiate callback recover_prompt recover).include?(action_name)
  end

  # POST /enterprises/:slug/oidc/initiate
  def initiate # rubocop:todo GitHub/UseRestfulActions
    record_sso_initiated

    # Calling the authorize endpoint in the IdP provider
    force_account_selection = params[:add_account] == "1"
    render "businesses/identity_management/sso_meta_redirect", locals: { redirect_url: oidc_authorize_url(force_account_selection: force_account_selection) }, layout: "layouts/redirect"
  end

  # Public: callback method used in the OIDC user authentication.
  #
  # Redirects to the "return_to" found in the relay state data hash
  def callback # rubocop:todo GitHub/UseRestfulActions
    result = validate_params
    raise AuthError.error(result) unless result.success?

    claims = result.claims
    relay_state = result.relay_state
    business = result.business
    authorization_code = result.authorization_code

    # Rotate the user's user_session cookie key. This will prevent bad actors with stolen user_session cookies
    # from access org/enterprise resources when the user's SAML session expires and they renew it.
    rotate_user_session_key(:oidc_authentication)

    if setup_provider_settings?(relay_state)
      setup_path(claims, relay_state, business)
    else
      sign_in_authorize_path(claims, relay_state, business, authorization_code)
    end
  rescue AuthError => error
    log \
      "controller" => self.class.name,
      "action" => __method__,
      "info.message" => "OIDC SSO failed",
      "at" => error.at,
      "login" => error.login, # rubocop:disable GitHub/DoNotAllowLogin error is not a User object
      "error" => error.message,
      "sso_error" => error.sso_error,
      "errors" => error.errors,
      "params" => request.params
    flash[:error] = error.message
    flash[:oidc_error] = error.sso_error

    record_sso_completed(error.sso_error, claims, relay_state, business, error_message: error.message)

    business = GitHub::CurrentTenant.get if GitHub.multi_tenant_enterprise?

    # This feature flag will not cover all of the cases, since business
    # can be null here, but it will cover some of them
    safe_redirect_to enterprise_redirect_url(success: false, business: business)
  end

  # Revokes the currently active external identity session for this business.
  # DELETE /enterprises/:slug/oidc/revoke
  def revoke # rubocop:todo GitHub/UseRestfulActions
    if session = current_external_identity_session(target: this_business)
      session.destroy
    end

    if request.xhr?
      head :ok
    else
      redirect_to "#{enterprise_url(this_business)}/sso"
    end
  end

  # Render a form to enter a recovery code.
  # GET /enterprises/:slug/oidc/recover
  def recover_prompt # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(Businesses::IdentityManagement::SingleSignOnView, {
      business: this_business,
    })
    render "businesses/identity_management/recover",
      locals: { view: view, first_emu_admin_partial_sign_in: first_emu_admin_partially_signed_in? },
      layout: "layouts/session_authentication"
  end

  # Verify the recovery code provided and skip OIDC SSO by creating a
  # temporary ExternalIdentitySession for the user.
  # POST /enterprises/:slug/oidc/recover
  def recover # rubocop:todo GitHub/UseRestfulActions
    if params[:recovery_code]
      if this_business.external_provider.verify_recovery_code!(params[:recovery_code])
        if session[:recovery_code_required_user].present? &&
          this_business.enterprise_managed_user_enabled? &&
          (attempted_user = User.find_by_login(session[:recovery_code_required_user])).present? &&
          this_business.is_first_emu_owner?(user: attempted_user)
          # Log the first emu admin in
          login_user attempted_user, sign_in_verification_method: :first_emu_recovery_code_user
          flash[:notice] = "Your recovery code was accepted."
          set_emu_admin_recovery_session(this_business, RECOVERY_SESSION_EXPIRY.from_now)
          safe_redirect_to session[:return_to] || enterprise_path(this_business)
          return
        else
          if external_identity = this_business.external_provider.external_identities.linked_to(current_user).first
            # Set temporary external identity session
            update_or_create_external_identity_session external_identity,
              expires_at: RECOVERY_SESSION_EXPIRY.from_now

            flash[:notice] = "Your recovery code was accepted."
            redirect_to settings_security_enterprise_path(this_business)
            return
          elsif this_business.enterprise_managed_user_enabled? &&
            current_user.enterprise_managed_business == this_business &&
            current_user.is_first_emu_owner?

            set_emu_admin_recovery_session(this_business, RECOVERY_SESSION_EXPIRY.from_now)

            flash[:notice] = "Your recovery code was accepted."
            redirect_to enterprise_single_sign_on_configuration_path(this_business)
            return
          else
            flash[:error] = "You must have authenticated via SSO at least once."
          end
        end
      else
        flash[:error] = "Your recovery code was invalid."
      end
    end
    recover_prompt
  end

  private

  def business_oidc_required
    render_404 unless this_business&.oidc_provider.present?
  end

  # Private: This is the method executed during setup path
  # Returns nothing
  def setup_path(claims, relay_state, business)
    record_sso_completed(:success, claims, relay_state, business)

    # create tmp provider in order to cache recovery code & tenant id
    tmp_provider = Business::OIDCProvider.new(business: business, oidc_provider: relay_state.data["setup"], tenant_id: claims[:tid])

    cache_setup_values(tmp_provider, relay_state.data["migrate_to_oidc"])

    redirect_to settings_oidc_provider_recovery_codes_enterprise_path(
      slug: business.slug,
      oidc_provider_key: relay_state.data["setup"]
    )
  end

  # Private: This is the method executed during sign in/authorize
  # Returns nothing
  def sign_in_authorize_path(claims, relay_state, business, authorization_code)
    # validate that that the user has an external id and create a session
    # pat and ssh authorization calls will need to provide a different
    # validation where the session is not created but matched to the
    # external_identity that was selected based on the claims
    validate_and_sign_in_user(claims, relay_state, business, authorization_code)

    record_sso_completed(:success, claims, relay_state, business)

    if authorize_credential?(relay_state)
      authorize_credential(relay_state, business)
    else
      if form_data = form_data_for_replay(relay_state)
        view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
          business: business,
          form_data: form_data,
        })

        # Non-GET request was enforced. Prompt user to replay to request.
        render "businesses/identity_management/replay_enforced_request",
          locals: { view: view },
          layout: "layouts/session_authentication"
      else
        safe_redirect_to enterprise_redirect_url(relay_state: relay_state, business: business)
      end
    end
  end

  # Private: Get the redirect URL for successful and unsuccessful sign in
  #
  # Returns String
  def enterprise_redirect_url(success: true, relay_state: nil, business: nil)
    if success
      if business&.member?(current_user)
        relay_state.data["return_to"] || enterprise_url(business)
      elsif business
        relay_state.data["return_to"] || business_idm_sso_enterprise_path(business)
      else
        relay_state.data["return_to"] || login_url
      end
    else
      if business
        business_idm_sso_enterprise_path(business)
      else
        login_url
      end
    end
  end

  # Private: Perform credential authorization and redirect to the correct view
  #
  # Returns nothing
  def authorize_credential(relay_state, business)
    if credential_authorization = authorize_credential_request(relay_state)
      # SSO flow was used to authorize a credential. Notify the user they're good to go.
      return_to = relay_state.data["return_to"] || user_path(credential_authorization.organization)
      return_to = sanitize_url(return_to)

      view = create_view_model(Businesses::IdentityManagement::CredentialAuthorizedView, {
        business: business,
        credential_authorization: credential_authorization,
        return_to: return_to,
      })

      render "businesses/identity_management/credential_authorized",
        locals: { view: view },
        layout: "layouts/session_authentication"
    elsif form_data = form_data_for_replay(relay_state)
      view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
        business: business,
        form_data: form_data,
      })

      # Non-GET request was enforced. Prompt user to replay to request.
      render "businesses/identity_management/replay_enforced_request",
        locals: { view: view },
        layout: "layouts/session_authentication"
    else
      GitHub.logger.info("Unexpected request for credential authorization", {
        "code.function" => __method__,
        "gh.business.slug" => business.slug,
        "gh.business.id" => business.id,
        "gh.request_id" => relay_state.request_id,
      })

      safe_redirect_to enterprise_redirect_url(relay_state: relay_state, business: business)
    end
  end

  # Private: Check if the oid sso call was to setup a provider
  #
  # Returns Boolean
  def setup_provider_settings?(relay_state)
    !!relay_state.data["setup"]
  end

  # Private: Check if the call was initiated to authorize a credential
  #
  # Returns Boolean
  def authorize_credential?(relay_state)
    !!relay_state.data["organization_id"] && !!relay_state.data["credential_id"]
  end

  # Private: Validate user, create an external identity session if the call is an SSO call.
  #   For pat and ssh authorization matches the session with the external identity.
  #
  # Returns Boolean
  def validate_and_sign_in_user(claims, relay_state, business, authorization_code)
    oid = claims[:oid]
    external_identity = lookup_external_identity(oid, business.oidc_provider)

    if external_identity
      raise AuthError.identity_not_found(oid, user: current_user) if external_identity.user.nil?

      # if the call was made to authorize a credential make sure that the
      # user is singed in and has external identity that matches one found
      # and the external identity session exist
      if authorize_credential?(relay_state)
        raise AuthError.user_not_singed_in(oid, user: current_user) unless logged_in?
      else
        raise AuthError.could_not_obtain_refresh_token(oid, user: current_user) unless acquire_refresh_token(claims, relay_state, business, authorization_code, external_identity)
        login_user_with_external_identity_session(external_identity, claims)
      end


      return external_identity.user
    end

    raise AuthError.identity_not_found(oid, user: current_user)
  end

  # Private: Creates a user session, external identity session and authenticated device information
  # for the user who is trying to sign-in to an EMU enabled enterprise.
  # user_session would be created for the backing user account with an external identity session
  #
  # provisioning_result  - provision_or_update result after calling provisioner
  # claims - JWT claims
  #
  # Returns nothing.
  def login_user_with_external_identity_session(external_identity, claims)
    User.transaction do
      unless same_user_logged_in?(external_identity.user)
        authenticated_device = remember_device(external_identity.user)
        login_user(
          external_identity.user,
          authenticated_device: authenticated_device,
          sign_in_verification_method: :enterprise_managed_user
        )
      end

      session_expires_at = Time.at(claims[:exp]).to_s
      update_or_create_external_identity_session external_identity,
        expires_at: session_expires_at
    end
  end

  # Private: Creates or updates authenticated device for the user during single sign-on.
  # The external identity and associated user account would be updated with
  # an authenticated device based on current_device_id stored in cookies.
  #
  # user  - user attempting to sign-in
  #
  # Returns the authenticated device object
  def remember_device(user)
    return nil unless user.sign_in_analysis_enabled?

    _, authenticated_device = AuthenticatedDevice.find_device_or_create!(
      user,
      device_id: current_device_id,
      display_name: AuthenticatedDevice.generated_display_name(Browser.new(request.user_agent)),
    )

    authenticated_device
  end

  # Private: Attempts to find an external identity and the user account
  # using the details returned by the identity provider attached to the business.
  #
  # oid - the oid claim from the identity provider (external_id)
  # provider - the oidc provider
  #
  # Returns a Platform::Provisioning:Result
  def lookup_external_identity(oid, provider)
    external_identity = ExternalIdentity.by_provider(provider).is_active.where(external_id: oid)

    return if external_identity.nil?
    return unless external_identity.any?
    return head 500 if external_identity.count > 1
    external_identity.first
  end

  # Private: Validate business tenant id saved in the oidc provider matches
  #   one returned in the claims from the token.
  #
  # Returns Business or nil
  def validate_business(tenant_id, relay_state)
    # query business by (tenant id) tid claim
    business = Business.find_by(id: relay_state.data["business_id"])

    return unless business

    # Do not validate tenant id when the call to sso
    # was made to setup a provider with the tenant extracted
    # from the token claims (claims[:tid])
    unless setup_provider_settings?(relay_state)
      return unless business.oidc_provider
      return unless tenant_id == business.oidc_provider&.tenant_id
    end

    business
  end

  # Private: Consumes relay state by matching an existing relay state on a
  #  nonce, request id, and a digest.  Nonce and request id were set in the
  #  result from omniauth claims and session state.  Digests is read from a cookie
  #  which was set during initiate and creation of the relay state.
  #  If the digest does not match the old relay state digest
  #  the new relay state object is set to invalid.
  #
  # Returns OIDC::RelayState
  def consume_relay_state(request_id, nonce)
    digest = cookies.encrypted[:oidc_csrf_token]
    digest_legacy = cookies.encrypted[:oidc_csrf_token_legacy]

    record_oidc_cookie_usage(digest, digest_legacy)
    remove_oidc_cookies

    digest = digest.presence || digest_legacy.presence

    relay_state = OIDC::RelayState.consume(
      nonce: nonce,
      request_id: request_id,
      digest: digest
    )
  end

  # Private: Remove already used cookies
  #
  # Returns nothing
  def remove_oidc_cookies
    cookies.delete(:oidc_csrf_token, domain: cookie_domain)
    cookies.delete(:oidc_csrf_token_legacy, domain: cookie_domain)
  end

  # Private: Create a stat record for completion of the sso, regardless of the status
  #  of the relay state.
  #
  # Returns nothing
  def record_sso_completed(status, claims, relay_state, business, error_message: nil)
    relay_state_status =
      if relay_state.nil?
        :missing
      else
        if relay_state.ok?
          :ok
        else
          :invalid
        end
      end

    GitHub.dogstats.increment "oidc.sso_completed",
      tags: dogstats_request_tags + [
        "sso_result:#{status}",
        "oid:#{claims.present? && claims[:oid]}",
        "tid:#{claims.present? && claims[:tid]}",
        "business_id:#{business&.id}",
        "relay_state:#{relay_state_status}",
        "logged_in:#{authed_or_anon}",
        "return_to:#{relay_state.present? && relay_state.data["return_to"].present?}",
        "authorization_request:#{relay_state.present? && relay_state.data["credential_id"].present?}",
      ]

    # Instrument and write to the audit log
    unless business.nil?
      business.instrument :sso_response,
        protocol: :OIDC,
        id_column_name: :OID,
        name_id: claims.present? && claims[:oid],
        external_id: claims.present? && claims[:oid],
        result: status,
        relay_state: relay_state_status,
        tid: claims.present? && claims[:tid],
        errors: status != :success,
        error_messages: error_message
    end
  end

  # Keep track of which cookies are being presented. This will give
  # insight into browser adoption of the new cookie standards
  #
  # The meaning of the various cookie_presence states are:
  # both:               The browser has not implemented the SameSite=none restrictions
  # only_samesite_none: The browser has implemented the SameSite=none restriction
  # only_legacy:        The browser is one that needs the legacy workaround. This number
  #                     will drive when it's safe to remove the legacy cookies
  # missing:            An IdP-initiated response, so no cookie is expected.
  def record_oidc_cookie_usage(digest, digest_legacy)
    if digest.present? && digest_legacy.present?
      cookie_presence = "both"
    elsif digest.present? && digest_legacy.nil?
      cookie_presence = "only_samesite_none"
    elsif digest.nil? && digest_legacy.present?
      cookie_presence = "only_legacy"
      digest = digest_legacy
    else
      return # nothing to log
    end

    tags = ["cookie_presence:#{cookie_presence}"] + dogstats_request_tags
    GitHub.dogstats.increment "oidc.cookie_presence", tags: tags
  end

  # Private: Authorize the credential to access the organization specified in the relay state
  #
  # Returns Organization::CredentialAuthorization
  def authorize_credential_request(relay_state)
    # NOTE: fingerprint may be nil
    organization_id    = relay_state.data["organization_id"]
    credential_id      = relay_state.data["credential_id"]
    credential_type    = relay_state.data["credential_type"]
    fingerprint        = relay_state.data["fingerprint"]

    organization = Organization.find_by(id: organization_id)
    return unless organization.present? && credential_id.present? && credential_type.present?

    # find personal access token or ssh key to authorize
    credential = case credential_type
    when "OauthAccess"
      OauthAccessTokens.domain.personal_token_by_user_id_and_fingerprint(current_user.id, credential_id, fingerprint)
    when "PublicKey"
      if fingerprint.present?
        current_user.public_keys.with_fingerprint(fingerprint).
          find_by_id(credential_id)
      end
    end

    return unless credential.present?

    # authorize the personal access token or ssh key
    Organization::CredentialAuthorization.grant \
      organization: organization,
      credential: credential,
      actor: current_user
  end

  def form_data_for_replay(relay_state)
    return unless data = relay_state.present? && relay_state.data.presence

    data["form_data"]
  end

  # Check if the Response should be redirected via POST to the callback endpoint
  def repost_response?
    # user_session is present so a repost isn't necessary
    return false if logged_in?

    # only repost once
    return false if session.delete(:reposted_oidc_response)

    true
  end

  # Redirect incoming responses via POST to callback.
  # This will enable the user_session and other same site cookies to be available
  def repost_response
    # set a session variable so we don't keep looping
    session[:reposted_oidc_response] = true

    form_data = {
      "code" => params[CODE],
      "error" => params[ERROR],
      "error_reason" => params[ERROR_REASON],
      "error_description" => params[ERROR_DESCRIPTION],
      "id_token" => params[ID_TOKEN],
      "state" => params[STATE],
      "session_state" => params[SESSION_STATE],
      "_target" => "/auth/oidc/callback",
    }

    view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
      form_data: form_data
    })

    render "businesses/identity_management/replay_enforced_request",
      locals: { view: view },
      layout: "layouts/session_authentication"
  end

  def cache_setup_values(tmp_provider, migrate_to_oidc)
    tmp_provider.generate_secrets!

    setup_values = {
      "tenant_id" => tmp_provider.tenant_id,
      "secret" => tmp_provider.secret,
      "recovery_secret" => tmp_provider.recovery_secret,
      "recovery_codes" => tmp_provider.formatted_recovery_codes,
      "migrate_to_oidc" => migrate_to_oidc,
    }

    ExternalIdentities::KV.set("oidc_provider_setup:#{tmp_provider.business.id}", setup_values.to_json, expires: 1.hour.from_now)
  end

  def acquire_refresh_token(claims, relay_state, business, authorization_code, external_identity)
    res = authorization_code_access_token_request(business: business, authorization_code: authorization_code)

    if res.success?
      body = JSON.parse(res.body)
      refresh_token = body["refresh_token"]
      OIDC::CapValidator.instrument_refresh_token_event_and_cache_write(business, external_identity, refresh_token, request.remote_ip)

      action =
        if setup_provider_settings?(relay_state)
          "access_token_request.setup"
        else
          "access_token_request.login"
        end

      GitHub.logger.info(
        "code.function" => action,
        "http.status_code" => res.status,
        "gh.business.name" => business.shortcode,
        "gh.request_id" => relay_state.request_id,
        "enduser.id" => current_user,
        "gh.external_identities.oid" => claims[:oid],
        "gh.external_identities.email" => claims[:preferred_username],
      )
      true
    else
      Failbot.report(StandardError.new("Unable to get refresh token from AAD"), status: res.status, business: business.name, user_oid: claims[:oid])
      false
    end
  end

  def oidc_recover_rate_limit_key
    if first_emu_admin_partially_signed_in? && session[:recovery_code_required_user_id].present?
      "oidc_recover_limiter:#{session[:recovery_code_required_user_id]}"
    else
      "oidc_recover_limiter:#{current_user.id}"
    end
  end

  def oidc_recover_rate_limit_filter
    params[:recovery_code].present?
  end

  def oidc_recover_rate_limit_max
    10
  end

  def oidc_recover_rate_limit_log_key
    "oidc-recover"
  end

  def oidc_recover_rate_limit_record
    key = "oidc.recover_rate_limited"
    # TODO - remove once the second dogstats call has populated
    GitHub.dogstats.increment(key)
    GitHub.dogstats.increment("rate_limited", tags: ["subject:oidc", "action:recover"])
  end

  # prevents redirection of requests with invalid user_session cookies, otherwise users with expired user_session cookies
  # belonging to an SSO-enabled business my be unable to access the SSO flow
  def redirect_invalid_user_sessions?
    false
  end
end
