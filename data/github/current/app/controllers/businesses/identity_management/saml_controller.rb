# typed: true
# frozen_string_literal: true

class Businesses::IdentityManagement::SamlController < Businesses::BusinessController
  include FeatureFlagHelper
  include SsoHelper
  include IdentityManagement::IdentityRelinkSamlControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    only: [:metadata]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:recover_prompt]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:recover_prompt], optional: true

  # How long does an admin's recovery session last?
  RECOVERY_SESSION_EXPIRY = 24.hours

  before_action :dotcom_required

  # For first EMU admins login, we are partially signing them in if they do not have 2FA
  # We require them to enter the recovery code to bypass SSO and to be fully logged in
  before_action :login_required, unless: :first_emu_admin_partially_signed_in?, except: %w(metadata initiate consume)
  before_action :business_owner_required, unless: :first_emu_admin_partially_signed_in?, only: %w(recover_prompt recover)
  # This should be before any filters that require a user session after consume
  before_action :repost_saml_response, if: :repost_saml_response?, only: %w(consume continue)
  before_action :resume_consume_on_staff_host, only: %w(consume continue)
  before_action :saml_config_required, except: %w(metadata)

  skip_before_action :verify_authenticity_token, only: [:consume]

  # The following actions do not need the EMU multi-tenancy policy.
  # We allow logged in users to be able to switch to an emu account
  def tenant_verification_enforceable # rubocop:todo GitHub/UseRestfulActions
    return :no if %w(initiate consume continue).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    :yes
  end

  # The following actions do not need the EMU visibility policy.
  # We expect anon requests to be able to initiate SSO to login
  def emu_visibility_enforceable # rubocop:todo GitHub/UseRestfulActions
    return :no if %w(initiate consume continue).include?(action_name)
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    :yes
  end

  # The following actions do not need the EMU ownership policy.
  # We allow logged in users to be able to switch to an emu account
  def emu_ownership_enforceable # rubocop:todo GitHub/UseRestfulActions
    return :no if %w(recover_prompt recover).include?(action_name) && first_emu_admin_partially_signed_in?
    return :yes unless this_business&.sso_redirect_enabled?
    return :no if %w(initiate consume continue).include?(action_name)
    :yes
  end

  # Override that determines whether an individual controller action should have
  # IP allow list enforcement applied.
  #
  # The following actions do not require IP allow list enforcement:
  #
  # - metadata: serves `/enterprises/:slug/saml/metadata`, public metadata about this
  #   business's SAML SSO configuration
  # - consume: serves `/enterprises/:slug/saml/consume`, consumes SAML response,
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
  # - metadata: serves `/enterprises/:slug/saml/metadata`, public metadata about this
  #   business's SAML SSO configuration
  # - initiate: serves `/enterprises/:slug/saml/initiate`, initiates SSO
  # - consume: serves `/enterprises/:slug/saml/consume`, consumes SAML response,
  #   creating SAML sessions (when successful)
  # - continue: serves `/orgs/:org/saml/continue`, continues consuming SAML
  #   response when successful (used for identity relink warnings)
  # - recover_prompt: serves `GET /enterprises/:slug/saml/recover`, allows admins to
  #   enter a recovery code to bypass SSO; POSTs to `/enterprises/:slug/saml/recover`
  # - recover: serves `POST /enterprises/:slug/saml/recover`, allows admins to submit
  #   a recovery code to bypass SSO
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

  delegate :saml_provider, to: :this_business
  delegate :issuer, to: :saml_provider
  delegate :sso_url, to: :saml_provider
  delegate :idp_certificate, to: :saml_provider
  delegate :signature_method, :digest_method, to: :saml_provider
  delegate :encrypted_assertions, :encryption_method, :key_transport_method, :key, to: :saml_provider

  # SAML metadata specific to the SSO flow for this business.
  # GET /enterprises/:slug/saml/metadata
  def metadata # rubocop:todo GitHub/UseRestfulActions
    return render_404 if this_business.nil?

    if this_business.feature_enabled?(:saml_lib_replacement_metadata)
      saml_metadata = Platform::Authentication::SAML.generate_metadata(
        assertion_consumer_service_url,
        enterprise_url(this_business)
      )
    else
      saml_metadata = ::SAML::Message::Metadata.new \
        assertion_consumer_service_url: assertion_consumer_service_url,
        sign_assertions: false,
        encrypted_assertions: false,
        issuer: enterprise_url(this_business),
        name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified"
    end

    render xml: saml_metadata
  end

  # POST /enterprises/:slug/saml/initiate
  def initiate # rubocop:todo GitHub/UseRestfulActions
    # Initialize relay_state and authn_request with T.nilable types to maintain consistent typing across our different FF branches.
    # This ensures Sorbet recognizes that these variables can hold either nil or their respective types,
    # preventing type change errors when different FFs assign different types.
    relay_state = T.let(nil, T.nilable(String))
    authn_request = T.let(nil, T.nilable(Platform::Authentication::SAML::Authrequest))

    if this_business.feature_enabled?(:ruby_saml_bounty_testing)
      authn_request = Platform::Authentication::SAML::Authrequest.new
      relay_state = initiate_relay_state(authn_request)
      authn_request_url = initiate_candidate_logic(authn_request, relay_state)
    elsif GitHub.flipper[:saml_lib_replacement_project].enabled? && this_business.feature_enabled?(:saml_lib_replacement_business_initiate)
      authn_request_url = science "validate_saml_lib_replacement_business_initiate" do |e|
        e.use do
          current_authn_request_url_generation
        end
        e.try do
          authn_request = Platform::Authentication::SAML::Authrequest.new
          # skipping the relay state initialization to prevent setting the wrong CSRF tokens
          # we do not compare relay state values in the science experiment - we are only concerned with the SAML
          # AuthN request, since that's what the library is responsible for.
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
    render "businesses/identity_management/sso_meta_redirect", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
  end

  # POST /enterprises/:slug/saml/consume
  def consume # rubocop:todo GitHub/UseRestfulActions
    if validate_provider_settings?
      validate_provider_settings
    else
      consume_saml_response(skip_identity_relink_checks: false)
    end
  end

  # POST /enterprises/:slug/saml/continue
  def continue # rubocop:todo GitHub/UseRestfulActions
    if validate_saml_continue_session(this_business)
      # at this point, we should have already validated that the user will relink their identity
      consume_saml_response(skip_identity_relink_checks: true)
    else
      render "pages_auth/forbidden",
        layout: "site",
        status: :forbidden,
        formats: [:html]
    end
  end

  # Revokes the currently active external identity session for this business.
  # DELETE /enterprises/:slug/saml/revoke
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
  # GET /enterprises/:slug/saml/recover
  def recover_prompt # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(Businesses::IdentityManagement::SingleSignOnView, {
      business: this_business,
    })
    render "businesses/identity_management/recover",
      locals: { view: view, first_emu_admin_partial_sign_in: first_emu_admin_partially_signed_in? },
      layout: "layouts/session_authentication"
  end

  # Verify the recovery code provided and skip SAML SSO by creating a
  # temporary ExternalIdentitySession for the user.
  # POST /enterprises/:slug/saml/recover
  def recover # rubocop:todo GitHub/UseRestfulActions
    if params[:recovery_code]
      if this_business.saml_provider.verify_recovery_code!(params[:recovery_code])
        if session[:recovery_code_required_user].present? &&
          this_business.enterprise_managed_user_enabled? &&
          (attempted_user = User.find_by_login(session[:recovery_code_required_user])).present? &&
          this_business.is_first_emu_owner?(user: attempted_user)
          # If the first EMU admin does not have 2FA enabled, we partially sign them in
          # and require them to enter the recovery code to fully sign in
          login_user attempted_user, sign_in_verification_method: :first_emu_recovery_code_user
          flash[:notice] = "Your recovery code was accepted."
          set_emu_admin_recovery_session(this_business, RECOVERY_SESSION_EXPIRY.from_now)
          safe_redirect_to session[:return_to] || enterprise_path(this_business)
          return
        else
          if external_identity = this_business.saml_provider.external_identities.linked_to(current_user).first
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
            flash[:error] = "You must have authenticated via SAML SSO at least once."
          end
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

  def consume_control_logic(saml_response)
    saml_consumer = Platform::Authentication::SamlConsumer.new(
      sp_url: service_provider_url,
      idp_certificate: idp_certificate,
      issuer: issuer,
      signature_method: signature_method,
      digest_method: digest_method,
      require_admin: false
    )
    saml_consumer.perform(saml_response)
  end

  def consume_candidate_logic(saml_response)
    Platform::Authentication::SAML.process_response(
      this_business,
      saml_response,
      assertion_consumer_service_url: assertion_consumer_service_url,
      sp_url: service_provider_url,
      idp_certificate: idp_certificate,
      issuer: issuer,
      signature_method: signature_method,
      digest_method: digest_method,
    )
  end

  def current_authn_request_url_generation
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

    authn_request_url
  end

  memoize def test_settings
    Business::SamlProviderTestSettings.most_recent_for(
      user: current_user,
      business: this_business,
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
    if logged_in? && this_business.actor_can_write_sso?(current_user)
      flash[:saml_test_result] = { status: nil, message: nil }

      saml_consumer = Platform::Authentication::SamlConsumer.new \
        sp_url: service_provider_url,
        idp_certificate: test_settings.idp_certificate,
        issuer: test_settings.issuer,
        signature_method: test_settings.signature_method,
        digest_method: test_settings.digest_method,
        require_admin: false
      auth_result = saml_consumer.perform(params[:SAMLResponse])

      # if SAMLResponse is successful, verify the RelayState, and possibly
      # override with Invalid state if that fails.
      if auth_result.success? && auth_result.assertion.in_response_to.present?
        relay_state = consume_relay_state(auth_result)

        if relay_state.ok? && test_settings.valid?
          flash[:saml_test_result][:status] = Business::SamlProviderTestSettings::SUCCESS
          flash[:saml_test_result][:message] = "Your SAML provider settings have been validated. Remember to save your changes."
          flash[:notice] = flash[:saml_test_result][:message]
        else
          # override result to be invalid if relay state isn't valid
          auth_result = Platform::Authentication::SamlResult.invalid(auth_result.assertion)
          log \
            at: "failure - invalid relay state",
            login: auth_result.assertion.name_id || "_unknown",
            errors: auth_result.assertion.errors,
            params: request.params
          flash[:saml_test_result][:status] = Business::SamlProviderTestSettings::FAILURE
          flash[:saml_test_result][:message] = saml_validation_error_message(auth_result, test_settings, required_relay_state: relay_state)
          flash[:error] = "Single sign-on via your configured IdP failed."
        end
      else
        flash[:saml_test_result][:status] = Business::SamlProviderTestSettings::FAILURE
        flash[:saml_test_result][:message] = saml_validation_error_message(auth_result, test_settings)
        flash[:error] = "Single sign-on via your configured IdP failed."
      end

      if flash[:saml_test_result][:status] == Business::SamlProviderTestSettings::FAILURE
        error = Business::SamlProviderTestSettings::InvalidSamlResponseError.new(flash[:saml_test_result][:message])
        error.set_backtrace(caller)
        Failbot.report!(error)
      end

      if this_business.enterprise_managed_user_enabled?
        redirect_to edit_enterprise_saml_provider_path(this_business)
      else
        redirect_to settings_security_enterprise_path(this_business)
      end
    else
      access_denied
    end
  end

  def consume_saml_response(skip_identity_relink_checks: true)
    # if an org has test settings but no saved provider, return a 404
    # safeguards against an exception that exposes HTTP ENV
    render_404 and return if saml_provider.nil?

    if this_business.feature_enabled?(:use_dual_saml_implementations)
      control_auth_result = consume_control_logic(params[:SAMLResponse])
      candidate_auth_result = consume_candidate_logic(params[:SAMLResponse])

      # `consume_match?` will check if one of the two was invalid, OR if they both failed, but for different reasons.
      # Either case will be logged.
      auth_result = if !Platform::Authentication::SAML.consume_match?(control_auth_result, candidate_auth_result, "business", this_business)
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
      saml_consumer = Platform::Authentication::SamlConsumer.new(
        sp_url: service_provider_url,
        idp_certificate: idp_certificate,
        issuer: issuer,
        signature_method: signature_method,
        digest_method: digest_method,
        require_admin: false
      )
      auth_result = saml_consumer.perform(params[:SAMLResponse])
    end

    # if SAMLResponse is successful, verify the RelayState, and possibly
    # override with Invalid state if that fails.
    if auth_result.success? && auth_result.assertion.in_response_to.present?
      relay_state = consume_relay_state(auth_result)

      if relay_state.ok?
        session[:org_invitation_id] = (relay_state.data || Hash.new)["org_invitation_id"].presence
        auth_result.redirect_url = (relay_state.data || Hash.new)["return_to"].presence
      else
        # override result to be invalid if relay state isn't valid
        auth_result = Platform::Authentication::SamlResult.invalid(auth_result.assertion)
      end
    end

    if auth_result.success?
      # check to see if the user will be relinked to a new identity as part of provisioning
      # this will redirect the flow to the relink warning page if necessary
      identity_will_be_relinked = check_for_identity_relink(
        target: this_business,
        skip_identity_relink_checks: skip_identity_relink_checks,
        auth_result: auth_result,
        relay_state: relay_state,
        provisioner: Platform::Provisioning::IdentityProvisioner,
      )
      # the relink warning will be rendered, so we can return here
      return if identity_will_be_relinked

      # Rotate the user's user_session cookie key. This will prevent bad actors with stolen user_session cookies
      # from access org/enterprise resources when the user's SAML session expires and they renew it.
      rotate_user_session_key(:saml_authentication)

      if this_business.enterprise_managed_user_enabled?
        lookup_result = Platform::Provisioning::EnterpriseManagedIdentityProvisioner.find_user_in_scim_managed_enterprise \
          user_data: auth_result.user_data,
          target: this_business,
          mapper: Platform::Provisioning::SamlMapper

        if lookup_result.success?
          login_user_with_external_identity_session(lookup_result, auth_result)

          if logged_in?
            if credential_authorization = authorize_credential_request(relay_state)
              # SSO flow was used to authorize a credential. Notify the user they're good to go.
              return_to = auth_result.redirect_url || user_path(credential_authorization.organization)
              return_to = sanitize_url(return_to)

              view = create_view_model(Businesses::IdentityManagement::CredentialAuthorizedView, {
                business: this_business,
                credential_authorization: credential_authorization,
                return_to: return_to,
              })
              render "businesses/identity_management/credential_authorized",
                locals: { view: view },
                layout: "layouts/session_authentication"
              return
            elsif form_data = form_data_for_replay(relay_state)
              view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
                business: this_business,
                form_data: form_data,
              })
              # Non-GET request was enforced. Prompt user to replay to request.
              render "businesses/identity_management/replay_enforced_request",
                locals: { view: view },
                layout: "layouts/session_authentication"
              return
            end
          else
            flash[:error] = "Unsuccessful SAML authentication."
            flash[:saml_error] = :unauthorized

            if this_business&.enterprise_managed_user_enabled?
              safe_redirect_to business_idm_sso_enterprise_path(this_business)
            else
              safe_redirect_to dashboard_url
            end
            return
          end
        else
          flash[:error] = "There was an issue joining the enterprise: #{lookup_result.errors.full_messages.to_sentence}"
          flash[:saml_error] = :provisioning

          if this_business&.enterprise_managed_user_enabled?
            safe_redirect_to business_idm_sso_enterprise_path(this_business)
          else
            safe_redirect_to dashboard_url
          end
          return
        end
      else
        provisioning_result = find_or_provision_external_identity(auth_result.user_data)

        unless provisioning_result.success?
          flash[:error] = "There was an issue joining the enterprise: #{ provisioning_result.errors.full_messages.to_sentence }"
          flash[:saml_error] = :provisioning
          redirect_url = auth_result.redirect_url || enterprise_saml_redirect_url(auth_result, enterprise_account: this_business)
          safe_redirect_to redirect_url
          return
        end

        if logged_in?
          update_or_create_external_identity_session provisioning_result.external_identity,
            expires_at: auth_result.assertion.session_expires_at

          if credential_authorization = authorize_credential_request(relay_state)
            # SSO flow was used to authorize a credential. Notify the user they're good to go.
            return_to = auth_result.redirect_url || user_path(credential_authorization.organization)
            return_to = sanitize_url(return_to)

            view = create_view_model(Businesses::IdentityManagement::CredentialAuthorizedView, {
              business: this_business,
              credential_authorization: credential_authorization,
              return_to: return_to,
            })
            # Non-GET request was enforced. Prompt user to replay to request.
            render "businesses/identity_management/credential_authorized",
              locals: { view: view },
              layout: "layouts/session_authentication"
            return
          elsif form_data = form_data_for_replay(relay_state)
            # Non-GET request was enforced. Prompt user to replay to request.
            view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
              business: this_business,
              form_data: form_data,
            })
            # Non-GET request was enforced. Prompt user to replay to request.
            render "businesses/identity_management/replay_enforced_request",
              locals: { view: view },
              layout: "layouts/session_authentication"
            return
          end
        else
          prompt_sign_in_or_sign_up provisioning_result.external_identity, auth_result
          return
        end
      end
    elsif auth_result.unauthorized?
      log \
        at: "failure - Unauthorized",
        login: auth_result.assertion.name_id || "_unknown",
        errors: auth_result.assertion.errors,
        params: request.params,
        business: this_business&.slug
      flash[:error] = "Unsuccessful SAML authentication."
      flash[:saml_error] = :unauthorized
    elsif auth_result.invalid?
      log \
        at: "failure - Invalid SAML response",
        login: get_name_id_from_auth_result(auth_result),
        errors: get_errors_from_auth_result(auth_result),
        params: request.params,
        business: this_business&.slug
      if this_business.adminable_by?(current_user)
        flash[:error] = "Invalid SAML message: #{auth_result.assertion.is_a?(Hash) ? auth_result.assertion[:errors] : auth_result.assertion.errors.join(" ")}"
      else
        flash[:error] = "Unable to authenticate your SAML session (invalid SAML message). Please try again or contact an administrator of your enterprise."
      end
      flash[:saml_error] = :invalid
    end

    redirect_url = auth_result.redirect_url || enterprise_saml_redirect_url(auth_result, enterprise_account: this_business)
    safe_redirect_to redirect_url
  ensure
    record_sso_completed(auth_result, relay_state) if auth_result
  end

  def enterprise_saml_redirect_url(auth_result, enterprise_account: nil, organization: nil)
    if auth_result.success?
      if enterprise_account&.member?(current_user)
        enterprise_url(enterprise_account)
      elsif organization
        user_path(organization)
      else
        dashboard_url
      end
    else
      if enterprise_account&.enterprise_managed_user_enabled?
        return business_idm_sso_enterprise_path(enterprise_account)
      end
      # Take user to their dashboard if SSO had failed - they may not have access
      # to the url they were trying to reach
      dashboard_url
    end
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

  # Private: Returns the appropriate assertion consumer url for a given environment
  #
  # Returns a String
  def assertion_consumer_service_url
    host = enterprise_url_host
    return idm_saml_consume_enterprise_url(this_business, host: host) if host.present?
    idm_saml_consume_enterprise_url(this_business)
  end

  def saml_config_required
    return if this_business&.saml_provider.present? || test_settings.persisted?
    render_404
  end

  # Private: Attempts to provision an external identity for the current_user
  # using the details returned by the identity provider.
  #
  # saml_user_data  - A Platform::Provisioning::UserData instance containing
  #                   user information provided by the IdP.
  #
  # Returns a Platform::Provisioning:Status
  def find_or_provision_external_identity(saml_user_data)
    if logged_in? && this_business.feature_enabled?(:enterprise_idp_provisioning)
      Platform::Provisioning::IdentityProvisioner.provision_and_add_member \
        target: this_business,
        user_id: current_user.id,
        user_data: saml_user_data,
        mapper: Platform::Provisioning::SamlMapper
    elsif logged_in?
      Platform::Provisioning::IdentityProvisioner.provision \
        target: this_business,
        user_id: current_user.id,
        user_data: saml_user_data,
        mapper: Platform::Provisioning::SamlMapper,
        org_invitation_id: session.delete(:org_invitation_id)
    else
      Platform::Provisioning::IdentityProvisioner.find \
        target: this_business,
        user_data: saml_user_data,
        mapper: Platform::Provisioning::SamlMapper
    end
  end

  # Private: Creates a user session, external identity session and authenticated device information
  # for the user who is trying to sign-in to an EMU enabled enterprise.
  # user_session would be created for the backing user account with an external identity session
  #
  # provisioning_result  - provision_or_update result after calling provisioner
  # auth_result - SAML assertion result
  #
  # Returns nothing.
  def login_user_with_external_identity_session(provisioning_result, auth_result)
    User.transaction do
      provisioned_user = provisioning_result.user
      if provisioned_user
        unless same_user_logged_in?(provisioned_user)
          authenticated_device = remember_device(provisioned_user)
          login_user(
            provisioned_user,
            authenticated_device: authenticated_device,
            sign_in_verification_method: :enterprise_managed_user
          )
        end

        update_or_create_external_identity_session provisioning_result.external_identity,
                  expires_at: auth_result.assertion.session_expires_at
      end
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

    new_record, authenticated_device = AuthenticatedDevice.find_device_or_create!(
      user,
      device_id: current_device_id,
      display_name: AuthenticatedDevice.generated_display_name(Browser.new(request.user_agent)),
    )

    authenticated_device
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
    session[:saml_user_data] = Platform::Provisioning::SamlUserData.persist(auth_result.user_data, target: this_business)
    session[:unlinked_session_expires_at] = auth_result.assertion.session_expires_at
    session[:sso_return_to] = auth_result.redirect_url.presence

    if external_identity&.user&.present?
      anonymous_flash[:notice] = "Sign in to your personal account to complete SSO for #{this_business.name}"
      redirect_to login_path(
        login: external_identity.user.display_login,
        return_to: business_idm_sso_sign_up_enterprise_path(this_business),
      )
    else
      redirect_to business_idm_sso_sign_up_enterprise_path(this_business)
    end
  end

  def initiate_relay_state(authn_request, data: {})
    data[:return_to] ||= params[:return_to] if params[:return_to].present?

    # Persist captured form data from enforced request so user
    # can replay it after SSO.
    data[:form_data] = params[:form_data] if params[:form_data]

    if params[:invitation_id]
      # Persist the invitation ID to allow tracking and acceptance
      # of invitations after the SAML SSO authentication flow.
      data[:org_invitation_id] = params[:invitation_id]
    end

    if credential_authorization_request.presence
      data.update credential_authorization_request_params_for(credential_authorization_request) || Hash.new
    end

    relay_state = Platform::Authentication::SamlRelayState.initiate(
      request_id: authn_request.id,
      data: data,
    )

    # persist the relay state digest for future validation
    # Cookie attributes are additionally set by by app/controller/application_controller/security_headers_dependency.rb
    # By default the :saml_csrf_token will have the SameSite=none attribute set from the secure_headers gem.
    # The :saml_csrf_legacy cookie does not have the SameSite=none attribute set. This is to accommodate
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

  def cookie_domain
    # Remove port numbers from the host name (mostly relevant for development)
    super.split(":").first
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

  def remove_saml_cookies
    cookies.delete(:saml_csrf_token, domain: cookie_domain)
    cookies.delete(:saml_csrf_token_legacy, domain: cookie_domain)
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

  def credential_authorization_request_params_for(request)
    return unless request.present?

    organization_id = request.data["organization_id"]
    credential_type = request.data["credential_type"]
    credential_id   = request.data["credential_id"]

    return unless organization_id && credential_type && credential_id

    organization = Organization.find_by(id: organization_id)

    return unless organization.present?

    credential = OauthAccessTokens.domain.by_user_and_id(current_user.id, credential_id) if credential_type == "OauthAccess"
    credential = current_user.public_keys.find_by_id(credential_id) if credential_type == "PublicKey"

    return unless credential.present?
    {
      organization_id: organization.id,
      credential_id: credential.id,
      credential_type: credential.class.name,
      fingerprint: credential.fingerprint
    }
  end

  # Check if the SAML Response should be redirected via POST to the consume endpoint
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
    return render_404 if this_business.nil?
    # set a session variable so we don't keep looping
    session[:reposted_saml_response] = true

    form_data = {
      "SAMLResponse" => params[:SAMLResponse],
      "RelayState" => params[:RelayState],
      "_target" => idm_saml_consume_enterprise_url(this_business),
    }

    view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
      business: this_business,
      form_data: form_data
    })
    render "businesses/identity_management/replay_enforced_request",
      locals: { view: view },
      layout: "layouts/session_authentication"
  end

  # Returns the staff host name to resume SAML SSO on if initiated from a
  # staff host, branch lab, review lab, or stafftools host (admin.github.com).
  #
  # Returns host name String or nil if not initiating SSO from a staff host.
  def employee_unicorn_relay_host
    # short circuit if the environment is codespaces in development mode;
    # this is needed for codespaces to allow devs to use SAML application with
    # codespaces hostname and does not require redirection from production
    return if GitHub.codespaces?

    # short circuit if the request host matches the root GitHub.com domain;
    # this is needed for the "lab" host (github-staff1) since it uses the same
    # hostname as production and doesn't require a relay.
    return if request.host == GitHub.host_domain

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
    return unless relay_host.end_with?("." + GitHub.host_domain)

    SecureHeaders.append_content_security_policy_directives(
      request,
      form_action: SAFE_RELAY_HOSTS,
    )

    form_data = {
      "SAMLResponse" => params[:SAMLResponse],
      "RelayState" => nonce,
      "_target" => idm_saml_consume_enterprise_url(this_business, host: relay_host),
    }

    view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
      business: this_business,
      form_data: form_data
    })
    render "businesses/identity_management/replay_enforced_request",
      locals: { view: view },
      layout: "layouts/session_authentication"
  end

  def credential_authorization_request
    return unless token = params[:authorization_request].presence

    Organization::CredentialAuthorization.consume_request(
      target: this_business,
      token: token,
      actor: current_user,
    )
  end

  def authorize_credential_request(relay_state)
    return unless data = relay_state.present? && relay_state.data.presence

    # NOTE: fingerprint may be nil
    organization_id    = data["organization_id"]
    credential_id      = data["credential_id"]
    credential_type    = data["credential_type"]
    fingerprint        = data["fingerprint"]

    organization = Organization.find_by(id: organization_id)
    return unless organization.present? && credential_id.present? && credential_type.present?

    # find personal access token to authorize
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

    # authorize the personal access token
    Organization::CredentialAuthorization.grant \
      organization: organization,
      credential: credential,
      actor: current_user
  end

  def form_data_for_replay(relay_state)
    return unless data = relay_state.present? && relay_state.data.presence

    data["form_data"]
  end

  def saml_recover_rate_limit_key
    if first_emu_admin_partially_signed_in? && session[:recovery_code_required_user_id].present?
      "saml_recover_limiter:#{session[:recovery_code_required_user_id]}"
    else
      "saml_recover_limiter:#{current_user.id}"
    end
  end

  def saml_recover_rate_limit_filter
    params[:recovery_code].present? && !first_emu_admin_partially_signed_in?
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
        saml_result: result_status,
        emu: this_business.enterprise_managed_user_enabled?
      }

      log log_fields
    end

    GitHub.dogstats.increment "saml.sso_completed",
    tags: dogstats_request_tags + [
      "emu:#{this_business.enterprise_managed_user_enabled?}",
      "saml_result:#{result_status}",
      "relay_state:#{relay_state_status}",
      "logged_in:#{authed_or_anon}",
      "return_to:#{params[:return_to].present?}",
      "authorization_request:#{params[:authorization_request].present?}",
    ]

    # Instrument and write to the audit log
    this_business.instrument :sso_response,
      name_id: auth_result_name_id,
      protocol: :SAML,
      id_column_name: :NameID,
      external_id: auth_result_name_id,
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
