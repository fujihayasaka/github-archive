# typed: true
# frozen_string_literal: true

class Orgs::IdentityManagement::SamlController < Orgs::Controller
  include IdentityManagement::IdentityRelinkSamlControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:metadata]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:recover_prompt]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:metadata, :recover_prompt], optional: true

  # How long does an admin's recovery session last?
  RECOVERY_SESSION_EXPIRY = 24.hours

  before_action :dotcom_required
  before_action :login_required, except: [:metadata, :initiate, :consume]
  before_action :organization_admin_required, only: [:recover_prompt, :recover]
  before_action :business_plus_required
  before_action :business_saml_configuration_prohibited
  # This should be before any filters that require a user session after consume
  before_action :repost_saml_response, if: :repost_saml_response?, only: %w(consume continue)
  before_action :resume_consume_on_staff_host, only: [:consume, :continue]
  before_action :saml_config_required, except: :metadata


  skip_before_action :verify_authenticity_token, only: [:consume]

  # Override that determines whether an individual controller action should have
  # IP allow list enforcement applied.
  #
  # The following actions do not require IP allow list enforcement:
  #
  # - metadata: serves `/orgs/:org/saml/metadata`, public metadata about this
  #   organization's SAML SSO configuration
  # - consume: serves `/orgs/:org/saml/consume`, consumes SAML response,
  #   creating SAML sessions (when successful)
  #
  # Returns Symbol.
  private def ip_allowlist_enforceable
    return :no if %w(metadata consume continue).include?(action_name)
    super
  end

  # Override that determines whether an individual controller action should have
  # conditional access policy enforcement applied.
  #
  # Since it is a SAML controller and IdP CAP is not supported, we always return `:no`.
  #
  # Returns Symbol.
  private def external_conditional_access_policy_enforceable
    :no
  end

  # Override that determines whether an individual controller action should have
  # external identity session enforcement applied.
  #
  # The following actions do not require external identity session enforcement:
  #
  # - metadata: serves `/orgs/:org/saml/metadata`, public metadata about this
  #   organization's SAML SSO configuration
  # - initiate: serves `/orgs/:org/saml/initiate`, initiates SSO
  # - consume: serves `/orgs/:org/saml/consume`, consumes SAML response,
  #   creating SAML sessions (when successful)
  # - continue: serves `/orgs/:org/saml/continue`, continues consuming SAML
  #   response when successful (used for identity relink warnings)
  # - recover_prompt: serves `GET /orgs/:org/saml/recover`, allows admins to
  #   enter a recovery code to bypass SSO; POSTs to `/orgs/:org/saml/recover`
  # - recover: serves `POST /orgs/:org/saml/recover`, allows admins to submit
  #   a recovery code to bypass SSO
  # - revoke: serves `DELETE /orgs/:org/saml/revoke`, allows a user to revoke
  #   their SAML session with the org
  #
  # Returns Boolean.
  private def require_active_external_identity_session?
    !%w(
      metadata
      initiate
      consume
      continue
      recover_prompt
      recover
      revoke
    ).include?(action_name)
  end

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: :recover,
    if: :saml_recover_rate_limit_filter,
    key: :saml_recover_rate_limit_key,
    log_key: :saml_recover_rate_limit_log_key,
    max: :saml_recover_rate_limit_max,
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL,
    at_limit: :saml_recover_rate_limit_record

  delegate :saml_provider, to: :this_organization
  delegate :issuer, to: :saml_provider
  delegate :sso_url, to: :saml_provider
  delegate :idp_certificate, to: :saml_provider
  delegate :signature_method, :digest_method, to: :saml_provider

  # SAML metadata specific to the SSO flow for this organization.
  # /orgs/:login/saml/metadata
  def metadata # rubocop:todo GitHub/UseRestfulActions
    if this_organization.business&.feature_enabled?(:ruby_saml_bounty_testing)
      saml_metadata = Platform::Authentication::SAML.generate_metadata(
        assertion_consumer_service_url,
        service_provider_url
      )
    elsif GitHub.flipper[:saml_lib_replacement_project].enabled? && this_organization.business&.feature_enabled?(:saml_lib_replacement_org_metadata)
      saml_metadata = science "validate_saml_lib_replacement_org_metadata" do |e|
        e.use do
          ::SAML::Message::Metadata.new \
            assertion_consumer_service_url: assertion_consumer_service_url,
            sign_assertions: false,
            encrypted_assertions: false,
            issuer: service_provider_url,
            name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
        end
        e.try do
          Platform::Authentication::SAML.generate_metadata(
            assertion_consumer_service_url,
            service_provider_url
          )
        end
        e.compare do |control, candidate|
          Platform::Authentication::SAML.metadata_match?(control, candidate)
        end
      end
    else
      saml_metadata = ::SAML::Message::Metadata.new \
        assertion_consumer_service_url: assertion_consumer_service_url,
        sign_assertions: false,
        encrypted_assertions: false,
        issuer: service_provider_url,
        name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
    end

    render xml: saml_metadata
  end

  # POST /orgs/:login/saml/initiate
  def initiate # rubocop:todo GitHub/UseRestfulActions
    # Initialize relay_state and authn_request with T.nilable types to maintain consistent typing across our different FF branches.
    # This ensures Sorbet recognizes that these variables can hold either nil or their respective types,
    # preventing type change errors when different FFs assign different types.
    relay_state = T.let(nil, T.nilable(String))
    authn_request = T.let(
      nil,
      T.nilable(
        T.any(
          Platform::Authentication::SAML::Authrequest,
          Platform::Authentication::SamlAuthnRequestUrl
        )
      )
    )

    if this_organization.business&.feature_enabled?(:ruby_saml_bounty_testing)
      authn_request = Platform::Authentication::SAML::Authrequest.new
      relay_state = initiate_relay_state(authn_request)
      authn_request_url = initiate_candidate_logic(authn_request, relay_state)
    elsif GitHub.flipper[:saml_lib_replacement_project].enabled? && this_organization.business&.feature_enabled?(:saml_lib_replacement_org_initiate)
      authn_request_url = science "validate_saml_lib_replacement_org_initiate" do |e|
        e.use do
          options = {
            sp_url: service_provider_url,
            sso_url: sso_url,
            assertion_consumer_service_url: assertion_consumer_service_url,
            destination: sso_url,
            issuer: service_provider_url,
            signature_method: signature_method,
            digest_method: digest_method,
            force_authn: params[:add_account] == "1"
          }

          authn_request = Platform::Authentication::SamlAuthnRequestUrl.new(options)
          authn_request.relay_state = initiate_relay_state(authn_request.request)
          authn_request
        end
        e.try do
          authn_request = Platform::Authentication::SAML::Authrequest.new
          # we intentionally do not initiate relay state so as to avoid setting CSRF cookies multiple times.
          relay_state = "EXPERIMENTAL_RELAY_STATE"
          Platform::Authentication::SAML.generate_authn_request_url(
            authn_request,
            relay_state,
            sso_url,
            service_provider_url,
            assertion_consumer_service_url,
            signature_method,
            digest_method,
            params[:add_account] == "1",
          )
        end
        e.compare do |control, candidate|
          Platform::Authentication::SAML.initiate_match?(control, candidate)
        end
      end
    else
      options = {
        sp_url: service_provider_url,
        sso_url: sso_url,
        assertion_consumer_service_url: assertion_consumer_service_url,
        destination: sso_url,
        issuer: service_provider_url,
        signature_method: signature_method,
        digest_method: digest_method,
        force_authn: params[:add_account] == "1"
      }

      authn_request_url = Platform::Authentication::SamlAuthnRequestUrl.new(options)
      authn_request_url.relay_state = initiate_relay_state(authn_request_url.request)
    end

    record_sso_initiated

    redirect_url = authn_request_url.to_s
    render "orgs/identity_management/sso_meta_redirect", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
  end

  # POST /orgs/:login/saml/consume
  def consume # rubocop:todo GitHub/UseRestfulActions
    if validate_provider_settings?
      validate_provider_settings
    else
      consume_saml_response(skip_identity_relink_checks: false)
    end
  end

  # POST /orgs/:login/saml/continue
  def continue # rubocop:todo GitHub/UseRestfulActions
    if validate_saml_continue_session(this_organization)
      # at this point, we should have already validated that the user will relink their identity
      consume_saml_response(skip_identity_relink_checks: true)
    else
      render "pages_auth/forbidden",
        layout: "site",
        status: :forbidden,
        formats: [:html]
    end
  end

  # Revokes the currently active external identity session for this organization.
  # POST /orgs/:login/saml/revoke
  def revoke # rubocop:todo GitHub/UseRestfulActions
    if session = current_external_identity_session(target: this_organization)
      session.destroy
    end

    if request.xhr?
      head :ok
    else
      redirect_to org_idm_sso_url(org: this_organization)
    end
  end

  # Render a form to enter a recovery code.
  # GET /orgs/:login/saml/recover
  def recover_prompt # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      Orgs::IdentityManagement::SingleSignOnView,
      organization: this_organization,
      layout: "layouts/session_authentication",
    )
    render "orgs/identity_management/recover", locals: { view: view }
  end

  # Verify the recovery code provided and skip SAML SSO by creating a
  # temporary ExternalIdentitySession for the user.
  # POST /orgs/:login/saml/recover
  def recover # rubocop:todo GitHub/UseRestfulActions
    if params[:recovery_code]
      if this_organization.saml_provider.verify_recovery_code!(params[:recovery_code])
        if external_identity = this_organization.saml_provider.external_identities.linked_to(current_user).first
          # Set temporary external identity session
          update_or_create_external_identity_session external_identity,
            expires_at: RECOVERY_SESSION_EXPIRY.from_now

          flash[:notice] = "Your recovery code was accepted."
          redirect_to settings_org_security_url(this_organization)
          return
        else
          flash[:error] = "You must have authenticated via SAML SSO at least once."
        end
      else
        flash[:error] = "Your recovery code was invalid."
      end
    end
    recover_prompt
  end

  private

  def initiate_candidate_logic(authn_request, relay_state)
    Platform::Authentication::SAML.generate_authn_request_url(
      authn_request,
      relay_state,
      sso_url,
      service_provider_url,
      assertion_consumer_service_url,
      signature_method,
      digest_method,
      params[:add_account] == "1",
    )
  end

  memoize def test_settings
    Organization::SamlProviderTestSettings.most_recent_for(
      user: current_user,
      org: this_organization,
    )
  end

  def validate_provider_settings?
    validate_provider_settings_cookie == "validate"
  end

  def validate_provider_settings_cookie
    saml_return_to = cookies.encrypted[:saml_return_to] || cookies.encrypted[:saml_return_to_legacy]

    cookies.delete :saml_return_to
    cookies.delete :saml_return_to_legacy

    saml_return_to
  end

  def validate_provider_settings
    if logged_in? && this_organization.adminable_by?(current_user)
      flash[:saml_test_result] = { status: nil, message: nil }

      saml_consumer = Platform::Authentication::SamlConsumer.new \
        sp_url: service_provider_url,
        idp_certificate: test_settings.idp_certificate,
        issuer: test_settings.issuer,
        signature_method: test_settings.signature_method,
        digest_method: test_settings.digest_method

      auth_result = saml_consumer.perform(params[:SAMLResponse])

      # if SAMLResponse is successful, verify the RelayState, and possibly
      # override with Invalid state if that fails.
      if auth_result.success? && auth_result.assertion.in_response_to.present?
        relay_state = consume_relay_state(auth_result)

        if relay_state.ok? && test_settings.valid?
          flash[:saml_test_result][:status] = Organization::SamlProviderTestSettings::SUCCESS
          flash[:saml_test_result][:message] = "Your SAML provider settings have been validated. Remember to save your changes."
          flash[:notice] = flash[:saml_test_result][:message]
        else
          # override result to be invalid if relay state isn't valid
          auth_result = Platform::Authentication::SamlResult.invalid(auth_result.assertion)
          log \
            at: "failure - invalid relay state during provider setting validation",
            login: auth_result.assertion.name_id || "_unknown",
            errors: auth_result.assertion.errors,
            params: request.params
          flash[:saml_test_result][:status] = Organization::SamlProviderTestSettings::FAILURE
          flash[:saml_test_result][:message] = saml_validation_error_message(auth_result, test_settings, required_relay_state: relay_state)
          flash[:error] = "Single sign-on via your configured IdP failed."
        end
      else
        flash[:saml_test_result][:status] = Organization::SamlProviderTestSettings::FAILURE
        flash[:saml_test_result][:message] = saml_validation_error_message(auth_result, test_settings)
        flash[:error] = "Single sign-on via your configured IdP failed."
      end

      if flash[:saml_test_result][:status] == Organization::SamlProviderTestSettings::FAILURE
        error = Organization::SamlProviderTestSettings::InvalidSamlResponseError.new(flash[:saml_test_result][:message])
        error.set_backtrace(caller)
        Failbot.report!(error)
      end

      extra_params = {}
      if cookies.encrypted[:show_onboarding_guide_tip]
        cookies.delete :show_onboarding_guide_tip
        extra_params[:show_onboarding_guide_tip] = true
      end
      redirect_to settings_org_security_url(this_organization, extra_params)
    else
      access_denied
    end
  end

  def consume_saml_response(skip_identity_relink_checks: true)
    # if an org has test settings but no saved provider, return a 404
    # safeguards against an exception that exposes HTTP ENV
    render_404 and return if saml_provider.nil?

    if this_organization.feature_enabled?(:use_dual_saml_implementations) || this_organization.business&.feature_enabled?(:use_dual_saml_implementations)
      control_auth_result = consume_control_logic(params[:SAMLResponse])
      candidate_auth_result = consume_candidate_logic(params[:SAMLResponse])

      # `consume_match?` will check if one of the two was invalid, OR if they both failed, but for different reasons.
      # Either case will be logged.
      auth_result = if !Platform::Authentication::SAML.consume_match?(control_auth_result, candidate_auth_result, "organization", this_organization)
        # If we've made it this far and the control was successful, it means that the candidate was not.
        # Given that we want the strictest implementation, we return the candidate error result.
        if control_auth_result.success?
          candidate_auth_result
        # Else the candidate was successful and the control was not, or both responses were invalid for different reasons.
        # In either case, it is fine to prefer the control for now to preserve the error.
        else
          control_auth_result
        end
      else
        # Otherwise both were successful, or both failed for the same reason. In either case, both results are the
        # same and we can safely return the control.
        control_auth_result
      end
    else
      saml_consumer = Platform::Authentication::SamlConsumer.new \
        sp_url: service_provider_url,
        idp_certificate: idp_certificate,
        issuer: issuer,
        signature_method: signature_method,
        digest_method: digest_method

      auth_result = saml_consumer.perform(params[:SAMLResponse])
    end

    # if SAMLResponse is successful, verify the RelayState, and possibly
    # override with Invalid state if that fails.
    if auth_result.success? && auth_result.assertion.in_response_to.present?
      relay_state = consume_relay_state(auth_result)

      if relay_state.ok?
        auth_result.redirect_url = (relay_state.data || Hash.new)["return_to"].presence
        session[:sso_invitation_token] = (relay_state.data || Hash.new)["sso_invitation_token"].presence
      else
        # override result to be invalid if relay state isn't valid
        auth_result = Platform::Authentication::SamlResult.invalid(auth_result.assertion)
      end
    end

    record_sso_completed(auth_result, relay_state)

    if auth_result.success?
      # check to see if the user will be relinked to a new identity as part of provisioning
      # this will redirect the flow to the relink warning page if necessary
      identity_will_be_relinked = check_for_identity_relink(
        target: this_organization,
        skip_identity_relink_checks: skip_identity_relink_checks,
        auth_result: auth_result,
        relay_state: relay_state,
        provisioner: Platform::Provisioning::OrganizationIdentityProvisioner
      )
      # the relink warning will be rendered, so we can return here
      return if identity_will_be_relinked

      # Rotate the user's user_session cookie key. This will prevent bad actors with stolen user_session cookies
      # from access org/enterprise resources when the user's SAML session expires and they renew it.
      rotate_user_session_key(:saml_authentication)

      provisioning_result = find_or_provision_external_identity(auth_result.user_data)

      unless provisioning_result.success?
        flash[:error] = "There was an issue joining the organization: #{ provisioning_result.errors.full_messages.to_sentence(words_connector: " ", last_word_connector: " ", two_words_connector: " ") }"
        flash[:saml_error] = :provisioning
        redirect_url = auth_result.redirect_url || user_url(this_organization)
        safe_redirect_to redirect_url
        return
      end

      if logged_in?
        update_or_create_external_identity_session provisioning_result.external_identity,
        expires_at: auth_result.assertion.session_expires_at

        if credential_authorization = authorize_credential_request(relay_state)
          # SSO flow was used to authorize a credential. Notify the user they're good to go.
          return_to = auth_result.redirect_url || user_url(this_organization)
          return_to = sanitize_url(return_to)
          view = create_view_model(
            Orgs::IdentityManagement::CredentialAuthorizedView,
            organization: this_organization,
            credential_authorization: credential_authorization,
            return_to: return_to,
          )
          render "orgs/identity_management/credential_authorized", layout: "layouts/session_authentication", locals: { view: view }
          return
        elsif form_data = form_data_for_replay(relay_state)
          # Non-GET request was enforced. Prompt user to replay to request.
          view = create_view_model(
            Orgs::IdentityManagement::ReplayEnforcedRequestView,
            organization: this_organization,
            form_data: form_data,
          )
          render "orgs/identity_management/replay_enforced_request", layout: "layouts/session_authentication", locals: { view: view }
          return
        end

        if provisioning_result.pending?
          return_to = auth_result.redirect_url || user_url(this_organization)
          return redirect_to org_reinstate_status_path(return_to: return_to)
        end
      else
        prompt_sign_in_or_sign_up provisioning_result.external_identity, auth_result
        return
      end
    elsif auth_result.unauthorized?
      log \
        at: "failure - Unauthorized",
        login: auth_result.assertion.name_id || "_unknown",
        errors: auth_result.assertion.errors,
        params: request.params,
        organization: this_organization&.display_login
      flash[:error] = "Unsuccessful SAML authentication."
      flash[:saml_error] = :unauthorized
    elsif auth_result.invalid?
      log \
        at: "failure - Invalid SAML response",
        login: get_name_id_from_auth_result(auth_result),
        errors: get_errors_from_auth_result(auth_result),
        params: request.params,
        organization: this_organization&.display_login
      if this_organization.adminable_by?(current_user)
        flash[:error] = "Invalid SAML message: #{auth_result.assertion.is_a?(Hash) ? auth_result.assertion[:errors] : auth_result.assertion.errors.join(" ")}"
      else
        flash[:error] = "Unable to authenticate your SAML session (invalid SAML message). Please try again or contact your organization administrator."
      end
      flash[:saml_error] = :invalid
    end

    redirect_url = auth_result.redirect_url || user_url(this_organization)
    safe_redirect_to redirect_url
  end

  def saml_validation_error_message(auth_result, test_settings, required_relay_state: :not_required)
    errors = auth_result.errors || []

    if !auth_result.assertion.in_response_to.present?
      errors << "InResponseTo was invalid or missing"
    end

    errors += test_settings.errors.full_messages

    if required_relay_state != :not_required && required_relay_state.invalid?
      errors << "RelayState is invalid"
    end

    errors.join(", ")
  end

  def assertion_consumer_service_url
    "#{service_provider_url}/saml/consume"
  end

  def service_provider_url
    if GitHub.staging_lab? || GitHub.codespaces?
      org_root_url(org: this_organization)
    else
      org_root_url(host: GitHub.host_domain, org: this_organization)
    end
  end

  def business_plus_required
    return if this_organization.business_plus?
    render_404
  end

  def business_saml_configuration_prohibited
    return if this_organization.business.blank? || this_organization.business.saml_provider.blank?
    render_404
  end

  def saml_config_required
    return if this_organization.saml_provider.present? || test_settings.persisted?
    render_404
  end

  private def consume_control_logic(saml_response)
    saml_consumer = Platform::Authentication::SamlConsumer.new \
      sp_url: service_provider_url,
      idp_certificate: idp_certificate,
      issuer: issuer,
      signature_method: signature_method,
      digest_method: digest_method

    saml_consumer.perform(params[:SAMLResponse])
  end

  private def consume_candidate_logic(saml_response)
    Platform::Authentication::SAML.process_response(
      this_organization,
      saml_response,
      sp_url: service_provider_url,
      assertion_consumer_service_url: assertion_consumer_service_url,
      idp_certificate: idp_certificate,
      issuer: issuer,
      signature_method: signature_method,
      digest_method: digest_method,
    )
  end

  # Private: Attempts to find or provision an external identity for the current_user
  # using the details returned by the identity provider.
  #
  # saml_user_data  - A Platform::Provisioning::UserData instance containing
  #                   user information provided by the IdP.
  #
  # Returns a Platform::Provisioning:Status
  def find_or_provision_external_identity(saml_user_data)
    if logged_in?
      Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_add_member \
        organization_id: this_organization.id,
        user_id: current_user.id,
        user_data: saml_user_data,
        mapper: Platform::Provisioning::SamlMapper,
        sso_invitation_token: session.delete(:sso_invitation_token)
    else
      Platform::Provisioning::OrganizationIdentityProvisioner.find \
        organization_id: this_organization.id,
        user_data: saml_user_data,
        mapper: Platform::Provisioning::SamlMapper
    end
  end

  # Private: Sends the user to a page prompting them to sign in or sign up.
  # The provisioned external identity is stored in the session so that we
  # can link it up after they are signed in.
  # If the external_identity is already linked to a GitHub account, we prompt
  # the user to sign in.
  #
  # external_identity - The ExternalIdentity provisioned during SAML SSO.
  # auth_result       - The consumed SAML::Message::Response.
  #
  # Returns nothing
  def prompt_sign_in_or_sign_up(external_identity, auth_result)
    session[:saml_user_data] = Platform::Provisioning::SamlUserData.persist(auth_result.user_data, target: this_organization)
    session[:unlinked_session_expires_at] = auth_result.assertion.session_expires_at
    session[:sso_return_to] = auth_result.redirect_url.presence

    if external_identity&.user&.present?
      anonymous_flash[:notice] = "Sign in to your personal account to complete SSO for #{this_organization.safe_profile_name}"
      redirect_to login_path(
        login: external_identity.user.display_login,
        return_to: org_idm_sso_sign_up_path(this_organization),
      )
    else
      redirect_to org_idm_sso_sign_up_path(this_organization)
    end
  end

  def initiate_relay_state(authn_request, data: {})
    data[:return_to] ||= params[:return_to] if params[:return_to].present?

    if params[:form_data]
      # Persist captured form data from enforced request so user
      # can replay it after SSO.
      data[:form_data] = params[:form_data].permit!.to_h
    end

    if params[:invitation_token]
      # Persist the invitation ID to allow tracking and acceptance
      # of invitations after the SAML SSO authentication flow.
      data[:sso_invitation_token] = params[:invitation_token]
    end

    if credential_authorization_request.presence
      data.update credential_authorization_request_params_for(credential_authorization_request) || Hash.new
    end

    relay_state = Platform::Authentication::SamlRelayState.initiate(
      request_id: authn_request.id,
      data: data,
    )

    # persist the relay state digest for future validation
    # Cookie attributes are additionally set by app/controller/application_controller/security_headers_dependency.rb
    # By default the :saml_csrf_token will have the SameSite=none attribute set from the secure_headers gem.
    # The :saml_csrf_legacy cookie does not have the SameSite=none attribute set. This is to accomodate
    # browsers that reject or mistreat cookies with the SameSite=none attribute. In particular, there is
    # a bug that treats SameSite=None and invalid values as Strict in macOS before 10.15 Catalina and in iOS before 13.
    cookies.encrypted[:saml_csrf_token] = saml_csrf_cookie(relay_state.digest)
    cookies.encrypted[:saml_csrf_token_legacy] = saml_csrf_cookie(relay_state.digest)

    [relay_state.nonce, employee_unicorn_relay_host].compact.join(";")
  end

  # Encrypted cookies have some odd behavior when the exact same object is used as a value
  # This reduces repetition while helping create valid cookies.
  def saml_csrf_cookie(digest)
    {
      value: digest,
      expires: ::Platform::Authentication::SamlRelayState::DEFAULT_EXPIRY,
      secure: request && request.ssl?,
      httponly: true,
      domain: cookie_domain,
    }
  end

  def consume_relay_state(auth_result)
    digest = cookies.encrypted[:saml_csrf_token]
    digest_legacy = cookies.encrypted[:saml_csrf_token_legacy]

    record_saml_cookie_usage(digest, digest_legacy)
    remove_saml_cookies

    digest = digest.presence || digest_legacy.presence

    Platform::Authentication::SamlRelayState.consume(
      nonce:  params[:RelayState],
      request_id: auth_result.success? && auth_result.assertion.in_response_to,
      digest: digest,
    )
  end

  # Keep track of which cookies are being presented. This will give
  # insight into browser adoption of the new cookie standards
  #
  # The meaning of the various cookie_presence states are:
  # both:               The browser has not implemented the SameSite=none restrictions
  # only_samesite_none: The browser has implemented the SameSite=none restriction
  # only_legacy:        The browser is one that needs the legacy workaround. This number
  #                     will drive when it's safe to remove the legacy cookies
  # missing:            An IdP-initiated SAML response, so no cookie is expected.
  def record_saml_cookie_usage(digest, digest_legacy)
    if digest.present? && digest_legacy.present?
      cookie_presence = "both"
    elsif digest.present? && digest_legacy.nil?
      cookie_presence = "only_samesite_none"
    elsif digest.nil? && digest_legacy.present?
      cookie_presence = "only_legacy"
      digest = digest_legacy
    elsif params[:RelayState].present?
      cookie_presence = "missing"
    else
      return # nothing to log
    end

    tags = ["cookie_presence:#{cookie_presence}"] + dogstats_request_tags
    GitHub.dogstats.increment "saml.cookie_presence", tags: tags
  end

  def remove_saml_cookies
    cookies.delete(:saml_csrf_token, domain: cookie_domain)
    cookies.delete(:saml_csrf_token_legacy, domain: cookie_domain)
  end

  def credential_authorization_request_params_for(request)
    return unless request.present?

    credential_type = request.data["credential_type"]
    credential_id   = request.data["credential_id"]

    return unless credential_type && credential_id

    credential = OauthAccessTokens.domain.user_access_by_id(current_user.id, credential_id) if credential_type == "OauthAccess"
    credential = current_user.public_keys.find_by_id(credential_id) if credential_type == "PublicKey"

    return unless credential.present?
    {
      credential_id: credential.id,
      credential_type: credential.class.name,
      fingerprint: credential.fingerprint
    }
  end

  # Check if the SAML Response shoudl be redirected via POST to the consume endpoint
  # Only needed if the user_session isn't present, and should only happen once.
  def repost_saml_response?
    # user_session is present so a repost isn't necessary
    return false if logged_in?

    # only repost once
    return false if session.delete(:reposted_saml_response)

    true
  end

  # Redirect incoming SAML responses via POST to consume.
  # This will enable the user_session and other same site cookies to be available
  def repost_saml_response
    # set a session variable so we don't keep looping
    session[:reposted_saml_response] = true

    form_data = {
      "SAMLResponse" => params[:SAMLResponse],
      "RelayState" => params[:RelayState],
      "_target" => org_idm_saml_consume_url(this_organization),
    }


    view = create_view_model(
      Orgs::IdentityManagement::ReplayEnforcedRequestView,
      organization: this_organization,
      form_data: form_data,
    )
    render "orgs/identity_management/replay_enforced_request", layout: "layouts/session_authentication", locals: { view: view }
  end

  # Returns the staff host name to resume SAML SSO on if initiated from a
  # staff host, branch lab, review lab, or stafftools host (admin.github.com).
  #
  # Returns host name String or nil if not initiating SSO from a staff host.
  def employee_unicorn_relay_host
    # short circuit if the request host matches the root GitHub.com domain;
    # this is needed for the "lab" host (github-staff1) since it uses the same
    # hostname as production and doesn't require a relay.
    return if request.host == GitHub.host_domain

    # Short circuit if we are running in codespaces and host_domain is set to `localhost`
    # There is a bug in GitHub.host_domain that returns `nil` if GH_HOSTNAME=localhost, even though it should return localhost. This means the previous return statement compares "localhost" with nil, so the short circuit does not trigger (even though it should)
    # Many other codepaths rely on the current behavior (some unintentionally), so we are adding a special exception here, so SAML auth on `localhost` is supported in codespaces
    return if GitHub.codespaces? && request.host == "localhost"

    # allow dev env to not require employee unicorn/admin host to test
    return request.host if Rails.env.development?

    # bail out if the current host is not an employee unicorn/admin host
    return unless GitHub.employee_unicorn? || GitHub.admin_host?

    request.host
  end

  SAFE_RELAY_HOSTS = [
    "*.#{GitHub.host_domain}",
  ].freeze

  # Redirect to the initiating staff host to consume the SAML Response.
  def resume_consume_on_staff_host
    return unless logged_in? && current_user.employee?
    return unless params[:RelayState].present?

    nonce, relay_host = params[:RelayState].split(";")
    return unless relay_host.present?
    # There is a bug in GitHub.host_domain that returns `nil` if GH_HOSTNAME=localhost, even though it should return localhost
    # Many other codepaths rely on the current behavior (some unintentionally), so we are adding a special exception here, so SAML auth on `localhost` is supported in codespaces
    # If this is not added, GitHub.host_domain will be nil, and ("." + nil) throws an exception
    return unless codespace_and_localhost?(relay_host) || relay_host.end_with?("." + GitHub.host_domain)

    SecureHeaders.append_content_security_policy_directives(
      request,
      form_action: SAFE_RELAY_HOSTS,
    )

    form_data = {
      "SAMLResponse" => params[:SAMLResponse],
      "RelayState" => nonce,
      "_target" => org_idm_saml_consume_url(this_organization, host: relay_host),
    }

    view = create_view_model(
      Orgs::IdentityManagement::ReplayEnforcedRequestView,
      organization: this_organization,
      form_data: form_data,
    )
    render "orgs/identity_management/replay_enforced_request", layout: "layouts/session_authentication", locals: { view: view }
  end

  def codespace_and_localhost?(relay_host)
    GitHub.codespaces? && GitHub.host_name == "localhost" && relay_host == "localhost"
  end
  private :codespace_and_localhost?

  def credential_authorization_request
    return unless token = params[:authorization_request].presence

    Organization::CredentialAuthorization.consume_request(
      target: this_organization,
      token: token,
      actor: current_user,
    )
  end

  def authorize_credential_request(relay_state)
    return unless data = relay_state.present? && relay_state.data.presence

    # NOTE: fingerprint may be nil
    credential_id      = data["credential_id"]
    credential_type    = data["credential_type"]
    fingerprint        = data["fingerprint"]

    return unless credential_id.present? && credential_type.present?

    # find personal access token to authorize
    credential = case credential_type
    when "OauthAccess"
      if current_user.feature_enabled?(:oauth_access_reads)
        OauthAccessTokens.domain.personal_token_by_id_and_fingerprint(current_user.id, credential_id, fingerprint)
      else
        current_user.oauth_accesses.personal_tokens.
        where(fingerprint: fingerprint).
        find_by_id(credential_id)
      end
    when "PublicKey"
      if fingerprint.present?
        current_user.public_keys.with_fingerprint(fingerprint).
          find_by_id(credential_id)
      end
    end
    return unless credential.present?

    # authorize the personal access token
    Organization::CredentialAuthorization.grant \
      organization: this_organization,
      credential: credential,
      actor: current_user
  end

  def form_data_for_replay(relay_state)
    return unless data = relay_state.present? && relay_state.data.presence

    data["form_data"]
  end

  def saml_recover_rate_limit_key
    "saml_recover_limiter:#{current_user.id}"
  end

  def saml_recover_rate_limit_filter
    params[:recovery_code].present?
  end

  def saml_recover_rate_limit_max
    10
  end

  def saml_recover_rate_limit_log_key
    "saml-recover"
  end

  def saml_recover_rate_limit_record
    key = "saml.recover_rate_limited"
    # TODO - remove once the second dogstats call has populated
    GitHub.dogstats.increment(key)
    GitHub.dogstats.increment("rate_limited", tags: ["subject:saml", "action:recover"])
  end

  # For tagging metrics
  def authed_or_anon
    logged_in? ? "auth" : "anon"
  end

  def record_sso_initiated
    GitHub.dogstats.increment "saml.sso_initiated",
      tags: dogstats_request_tags + [
        "logged_in:#{authed_or_anon}",
        "invitation:#{params[:invitation_token].present?}",
        "return_to:#{params[:return_to].present?}",
        "authorization_request:#{params[:authorization_request].present?}",
      ]
  end

  def record_sso_completed(auth_result, relay_state)
    result_status =
      if auth_result.success?
        :success
      else
        auth_result.failure_type
      end

    relay_state_status =
      if relay_state.nil?
        if params[:RelayState].present?
          :ignored
        else
          :missing
        end
      else
        if relay_state.ok?
          :ok
        else
          :invalid
        end
      end

    auth_result_name_id = get_name_id_from_auth_result(auth_result)
    auth_result_errors = get_errors_from_auth_result(auth_result)

    if relay_state_status == :missing || relay_state_status == :invalid
      log_fields = {
        at: "failure - invalid relay state",
        login: auth_result_name_id,
        errors: auth_result_errors,
        params: request.params,
        relay_state: relay_state_status,
        saml_result: result_status
      }

      log log_fields
    end

    GitHub.dogstats.increment "saml.sso_completed",
      tags: dogstats_request_tags + [
        "saml_result:#{result_status}",
        "relay_state:#{relay_state_status}",
        "logged_in:#{authed_or_anon}",
        "invitation:#{session[:sso_invitation_token].present?}",
        "return_to:#{params[:return_to].present?}",
        "authorization_request:#{params[:authorization_request].present?}",
      ]

    # log Responses (to the audit log)
    this_organization.instrument :sso_response,
      name_id: auth_result_name_id,
      result: result_status,
      relay_state: relay_state_status,
      issuer: issuer,
      errors: !auth_result.success?,
      error_messages: auth_result.assertion.is_a?(Hash) ? auth_result.assertion[:errors] : auth_result.errors
  end

  def get_name_id_from_auth_result(auth_result)
    if auth_result.assertion.is_a?(Hash)
      "_unknown"
    else
      auth_result.assertion&.name_id || "_unknown"
    end
  end

  def get_errors_from_auth_result(auth_result)
    if auth_result.assertion.is_a?(Hash)
      auth_result.assertion[:errors]
    else
      auth_result.assertion&.errors
    end
  end
end
