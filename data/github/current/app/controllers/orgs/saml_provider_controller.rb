# typed: true
# frozen_string_literal: true

module Orgs
  class SamlProviderController < Controller
    before_action :organization_admin_required
    before_action :saml_configuration_allowed, only: %w(update delete)
    before_action :saml_provider_required, only: %w(recovery_codes download_recovery_codes
      print_recovery_codes regenerate_recovery_codes)

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Billing,
      only: [:recovery_codes, :print_recovery_codes]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:recovery_codes, :print_recovery_codes],
      optional: true

    stylesheet_bundle :businesses

    def update
      if this_organization.business_plus?
        params[:saml] ||= {}
        if params[:test_settings]
          test_saml_config
        else
          save_saml_config
        end
      else
        render_404
      end
    end

    def delete # rubocop:todo GitHub/UseRestfulActions
      this_organization.saml_provider.try(:destroy)
      flash[:notice] = "SAML authentication is disabled"
      redirect_to settings_org_security_path(this_organization)
    end

    # GET: displays the SAML provider's SSO recovery codes to an organization
    # admin
    def recovery_codes # rubocop:todo GitHub/UseRestfulActions
      view = create_view_model(
        Orgs::SamlProvider::RecoveryCodesView,
        organization: this_organization,
        saml_provider: this_organization.saml_provider
      )
      render "orgs/saml_provider/recovery_codes", locals: { view: view }

      this_organization.instrument(:recovery_codes_viewed)
    end

    # PUT: regenerate the SAML provider's SSO recovery codes
    def regenerate_recovery_codes # rubocop:todo GitHub/UseRestfulActions
      this_organization.saml_provider.generate_recovery!
      if this_organization.saml_provider.save
        flash[:notice] = "New SSO recovery codes successfully generated."
      else
        flash[:error] = "Something went wrong. Please try again."
      end
      redirect_to settings_org_saml_provider_recovery_codes_path(this_organization)
    end

    # POST: sends the text version of the SAML SSO recovery codes to an
    # organization admin (E.g. a file download).
    def download_recovery_codes # rubocop:todo GitHub/UseRestfulActions
      codes = this_organization.saml_provider.formatted_recovery_codes
      send_data(
        codes.join("\r\n"),
        filename: "github-#{this_organization.display_login}-recovery-codes.txt",
      )

      this_organization.instrument(:recovery_codes_downloaded)
    end

    # GET: displays a print-ready version of the SAML SSO recovery codes for
    # the current organization's SAML provider.
    def print_recovery_codes # rubocop:todo GitHub/UseRestfulActions
      # The 'popup' layout requires this instance variable
      @page_class = "js-print-popup"

      respond_to do |format|
        format.html do
          view = create_view_model(
            Orgs::SamlProvider::RecoveryCodesView,
            layout: "layouts/popup",
            organization: this_organization,
            saml_provider: this_organization.saml_provider
          )
          render "orgs/saml_provider/print_recovery_codes", locals: { view: view }
        end
      end

      this_organization.instrument(:recovery_codes_printed)
    end

    private

    def saml_params
      return ActionController::Parameters.new if params[:saml].empty?

      params.require(:saml).permit %i[
        sso_url
        issuer
        idp_certificate
        enforced
        digest_method
        signature_method
        session_length_in_minutes
      ]
    end

    def first_time_enforcement?
      params["saml-already-enforced"] != "1"
    end

    def saml_provider_test_settings_params
      saml_params.except(:enforced, :session_length_in_minutes)
    end

    def saml_provider_required
      return if this_organization.saml_provider.present?
      render_404
    end

    def saml_configuration_allowed
      return if this_organization.business.blank? || this_organization.business.saml_provider.blank?
      render_404
    end

    def test_saml_config
      # Initiate a SAML SSO roundtrip using the provided settings, without
      # saving them to the Organization::SamlProvider
      test_settings = Organization::SamlProviderTestSettings.save_for(
        user: current_user,
        organization: this_organization,
        settings: saml_provider_test_settings_params,
      )
      if test_settings.valid?
        # Initialize relay_state and authn_request with T.nilable types to maintain consistent typing across our different FF branches.
        # This ensures Sorbet recognizes that these variables can hold either nil or their respective types,
        # preventing type change errors when different FFs assign different types.
        relay_state = T.let(nil, T.nilable(String))
        authn_request = T.let(nil, T.nilable(Platform::Authentication::SAML::Authrequest))

        if this_organization.business&.feature_enabled?(:ruby_saml_bounty_testing)
          authn_request = Platform::Authentication::SAML::Authrequest.new
          relay_state = initiate_relay_state(authn_request)
          authn_request_url = initiate_candidate_logic(authn_request, relay_state, test_settings)
        elsif GitHub.flipper[:saml_lib_replacement_project].enabled? && this_organization.business&.feature_enabled?(:saml_lib_replacement_org_provider_initiate)
          authn_request_url = science "validate_saml_lib_replacement_org_provider_initiate" do |e|
            e.use do
              current_authn_request_url_generation(test_settings)
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
                test_settings.sso_url,
                org_root_url(org: this_organization),
                org_idm_saml_consume_url(org: this_organization),
                test_settings.signature_method,
                test_settings.digest_method,
              )
            end
            e.compare do |control, candidate|
              Platform::Authentication::SAML.initiate_match?(control, candidate)
            end
          end
        else
          options = {
            sp_url: org_root_url(org: this_organization),
            sso_url: test_settings.sso_url,
            assertion_consumer_service_url: org_idm_saml_consume_url(org: this_organization),
            destination: test_settings.sso_url,
            issuer: org_root_url(org: this_organization),
            signature_method: test_settings.signature_method,
            digest_method: test_settings.digest_method,
          }

          authn_request_url = Platform::Authentication::SamlAuthnRequestUrl.new(options)
          authn_request_url.relay_state = initiate_relay_state(authn_request_url.request)
        end

        # We use "validate" as the cookie value in this action to allow the
        # consume endpoint to know that a user was trying to test their
        # provider settings after the SAML SSO post-back.
        cookies.encrypted[:saml_return_to] = "validate"
        cookies.encrypted[:saml_return_to_legacy] = "validate"
        cookies.encrypted[:show_onboarding_guide_tip] = true if params[:show_onboarding_guide_tip].present?

        allow_external_redirect_after_post(provider: test_settings)
        redirect_url = authn_request_url.to_s
        render "orgs/identity_management/sso_meta_redirect", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
      else
        test_settings_errors = test_settings.errors.full_messages.join(", ")
        flash.now[:saml_test_result] = { status: Organization::SamlProviderTestSettings::FAILURE, message: test_settings_errors }
        flash.now[:error] = "Your SAML provider test settings are invalid"

        view = create_view_model(
          Orgs::SecuritySettings::IndexView,
          organization: this_organization,
          business: this_organization.business,
          current_user: current_user,
          saml_provider: test_settings,
          team_sync_setup_flow: ::TeamSync::SetupFlow.new(organization: this_organization, actor: current_user)
        )
        render "orgs/security_settings/index", locals: { view: view }
      end
    end

    private def initiate_candidate_logic(authn_request, relay_state, test_settings)
      Platform::Authentication::SAML.generate_authn_request_url(
        authn_request,
        relay_state,
        test_settings.sso_url,
        org_root_url(org: this_organization),
        org_idm_saml_consume_url(org: this_organization),
        test_settings.signature_method,
        test_settings.digest_method,
      )
    end

    def current_authn_request_url_generation(test_settings)
      options = {
        sp_url: org_root_url(org: this_organization),
        sso_url: test_settings.sso_url,
        assertion_consumer_service_url: org_idm_saml_consume_url(org: this_organization),
        destination: test_settings.sso_url,
        issuer: org_root_url(org: this_organization),
        signature_method: test_settings.signature_method,
        digest_method: test_settings.digest_method,
      }

      authn_request_url = Platform::Authentication::SamlAuthnRequestUrl.new(options)
      authn_request_url.relay_state = initiate_relay_state(authn_request_url.request)

      authn_request_url
    end

    def save_saml_config
      # Save the settings to the Organization::SamlProvider
      provider = this_organization.saml_provider || this_organization.build_saml_provider
      provider.user_that_must_test_settings = current_user

      if !params[:saml].has_key?(:session_length_in_minutes) && this_organization.feature_enabled?(:org_saml_session_length_configurable)
        # If the session length is not sent in the params for some reason and the feature flag is enabled, set it to nil to remove the configured session length.
        # The current caller app/views/orgs/security_settings/index.html.erb always sends the `session_length_in_minutes` parameter when the flag is enabled, but leave this as a defensive mechanism in case that ever changes.
        params[:saml][:session_length_in_minutes] = nil
      elsif params[:saml].has_key?(:session_length_in_minutes) && !this_organization.feature_enabled?(:org_saml_session_length_configurable)
        # If the session length is set in the params and the feature flag is not enabled,
        # remove it from the params since the customer shouldn't be able to update the value.
        # When the flag is disabled the current caller app/views/orgs/security_settings/index.html.erb
        # doesn't send the `session_length_in_minutes` parameter, but a defensive mechanism in case that changes.
        params[:saml].delete(:session_length_in_minutes)
      end

      if provider.update(saml_params)
        flash[:notice] = "Your SAML provider settings were saved"
        if provider.enforced? && first_time_enforcement?
          RemoveUnlinkedSamlMembersFromOrganizationJob.perform_later(
            this_organization.id, current_user.id
          )
          return redirect_to settings_org_saml_provider_recovery_codes_path(this_organization)
        end

        extra_params = {}
        extra_params[:show_onboarding_guide_tip] = true if params[:show_onboarding_guide_tip]
        redirect_to settings_org_security_path(this_organization, extra_params)
      else
        flash.now[:error] = "Your SAML provider settings could not be saved"
        view = create_view_model(
          Orgs::SecuritySettings::IndexView,
          organization: this_organization,
          business: this_organization.business,
          current_user: current_user,
          saml_provider: provider,
          team_sync_setup_flow: ::TeamSync::SetupFlow.new(organization: this_organization, actor: current_user)
        )
        render "orgs/security_settings/index", locals: { view: view }
      end
    end

    def initiate_relay_state(authn_request)
      relay_state = if GitHub.flipper[:redis_relay_state].enabled?(this_organization)
        Platform::Authentication::SamlRedisRelayState.initiate(
          request_id: authn_request.id,
        )
      else
        Platform::Authentication::SamlRelayState.initiate(
          request_id: authn_request.id,
        )
      end

      # persist the relay state digest for future validation
      # Cookie attributes are additionally set by app/controller/application_controller/security_headers_dependency.rb
      # By default the :saml_csrf_token will have the SameSite=none attribute set from the secure_headers gem.
      # The :saml_csrf_legacy cookie does not have the SameSite=none attribute set. This is to accomodate
      # browsers that reject or mistreat cookies with the SameSite=none attribute. In particular, there is
      # a bug that treats SameSite=None and invalid values as Strict in macOS before 10.15 Catalina and in iOS before 13.
      cookies.encrypted[:saml_csrf_token] = saml_csrf_cookie(relay_state.digest)
      cookies.encrypted[:saml_csrf_token_legacy] = saml_csrf_cookie(relay_state.digest)

      relay_state.nonce
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
  end
end
