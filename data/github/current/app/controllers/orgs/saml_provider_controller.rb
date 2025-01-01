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
      ]
    end

    def first_time_enforcement?
      params["saml-already-enforced"] != "1"
    end

    def saml_provider_test_settings_params
      saml_params.except(:enforced)
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

    def save_saml_config
      # Save the settings to the Organization::SamlProvider
      provider = this_organization.saml_provider || this_organization.build_saml_provider
      provider.user_that_must_test_settings = current_user

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
