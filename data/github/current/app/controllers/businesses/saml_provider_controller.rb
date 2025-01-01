# typed: true
# frozen_string_literal: true

class Businesses::SamlProviderController < Businesses::BusinessController
  include BusinessesHelper

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :active_enterprise_required
  before_action :saml_provider_required, only: %w(recovery_codes regenerate_recovery_codes update_user_provisioning)
  before_action :enterprise_idp_provisioning_required, only: %w(update_user_provisioning)
  before_action :first_emu_owner_required, only: %w(delete)
  before_action :emu_business_required, only: %w(edit)
  before_action :not_oidc_business, only: %w(edit)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:recovery_codes]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:print_recovery_codes]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:recovery_codes, :print_recovery_codes],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:edit]

  def update
    params[:saml] ||= {}
    if params[:test_settings]
      test_saml_config
    else
      # Attempt to save the provided configuration, without showing the
      # recovery codes...
      # - If there's an existing provider.
      # - If we're creating a new provider and the recovery codes have
      #   been viewed (and hopefully downloaded).
      #
      # Otherwise, show the recovery codes view, prompting the user to download
      # their recovery codes.
      if this_business.saml_provider.present? || params[:recovery_codes_viewed]
        save_saml_config
      else
        validate_saml_config_and_show_recovery_codes
      end
    end
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    this_business.saml_provider&.destroy
    flash[:notice] = "SAML authentication is disabled"
    if this_business.feature_enabled?(:move_emu_sso_configuration_page) && this_business.enterprise_managed_user_enabled?
      redirect_to enterprise_single_sign_on_configuration_path(this_business)
    else
      redirect_to settings_security_enterprise_path(this_business)
    end
  end

  def recovery_codes # rubocop:todo GitHub/UseRestfulActions
    render "businesses/saml_provider/recovery_codes"

    this_business.instrument(:recovery_codes_viewed)
  end

  def download_recovery_codes # rubocop:todo GitHub/UseRestfulActions
    codes = if this_business.saml_provider.present?
      this_business.saml_provider.formatted_recovery_codes
    elsif saml_provider_setup_flow.pending?
      tmp_saml_provider.formatted_recovery_codes
    end
    return render_404 if codes.blank?

    send_data codes.join("\r\n"), filename: "github-#{this_business.slug}-recovery-codes.txt"
    this_business.instrument(:recovery_codes_downloaded)
  end

  def print_recovery_codes # rubocop:todo GitHub/UseRestfulActions
    # The "popup" layout requires this instance variable
    @page_class = "js-print-popup"
    respond_to do |format|
      format.html do
        if this_business.saml_provider.blank?
          if saml_provider_setup_flow.pending?
            new_setup_recovery_codes = tmp_saml_provider.formatted_recovery_codes
          else
            return render_404
          end
        end

        render "businesses/print_recovery_codes", layout: "layouts/popup", locals: {
          new_setup_recovery_codes: new_setup_recovery_codes.presence
        }
      end
    end

    this_business.instrument(:recovery_codes_printed)
  end

  def regenerate_recovery_codes # rubocop:todo GitHub/UseRestfulActions
    provider = this_business.saml_provider
    if provider.present?
      provider.generate_recovery!
      if provider.save
        flash[:notice] = "New SSO recovery codes successfully generated."
      else
        flash[:error] = provider.errors.full_messages.join(", ")
      end
    else
      flash[:error] = "This enterprise account does not have an identity provider set."
    end
    redirect_to settings_saml_provider_recovery_codes_enterprise_path(this_business)
  end

  def update_user_provisioning # rubocop:todo GitHub/UseRestfulActions
    if this_business.saml_provider.update(user_provisioning_params)
      notice = "User provisioning settings saved."

      if saml_deprovisioning_changed?
        this_business.expire_all_enterprise_sessions!(current_user: current_user)
        notice += " Please re-authenticate with your Identity Provider to continue."
      end
      flash[:notice] = notice
    else
      errors = this_business.saml_provider.errors.full_messages.join(", ")
      flash[:error] = "Unable to save your user provisioning settings. #{errors}"
    end

    redirect_to settings_security_enterprise_path(this_business)
  end

  def edit
    return render_404 unless this_business.feature_enabled?(:move_emu_sso_configuration_page)

    render "businesses/settings/identity_provider/edit_saml_configuration", locals: {
      params: params_for_saml_test_result
    }
  end

  private

  def saml_deprovisioning_changed?
    this_business.saml_provider.previous_changes.has_key?("saml_deprovisioning_enabled") &&
      this_business.saml_provider.saml_deprovisioning_enabled?
  end

  def user_provisioning_params
    return ActionController::Parameters.new if params[:business_saml_provider].blank?
    # This covers GitHub.flipper[:enterprise_idp_provisioning].enabled?(this_business) in enterprise_idp_provisioning_required
    params.require(:business_saml_provider).permit(:provisioning_enabled, :saml_deprovisioning_enabled)
  end

  def enterprise_idp_provisioning_required
    render_404 unless GitHub.flipper[:enterprise_idp_provisioning].enabled?(this_business)
  end

  def saml_params
    return ActionController::Parameters.new if params[:saml].empty?

    if GitHub.flipper[:saml_encrypted_assertions].enabled?(this_business)
      params.require(:saml).permit %i[
        sso_url
        issuer
        idp_certificate
        digest_method
        signature_method
        encrypted_assertions
        encryption_method
        key_transport_method
        recovery_secret
      ]
    else
      params.require(:saml).permit %i[
        sso_url
        issuer
        idp_certificate
        digest_method
        signature_method
        recovery_secret
      ]
    end
  end

  def validate_saml_config_and_show_recovery_codes
    saml_provider_setup_flow.new_setup saml_params
    tmp_saml_provider.user_that_must_test_settings = current_user
    if tmp_saml_provider.valid?
      render "businesses/saml_provider/recovery_codes", locals: {
        new_setup_recovery_codes: tmp_saml_provider.formatted_recovery_codes,
        new_setup_saml_params: saml_params.merge(recovery_secret: tmp_saml_provider.recovery_secret),
      }
    else
      errors = tmp_saml_provider.errors.full_messages.to_sentence
      flash.now[:error] = "Invalid SAML provider settings. #{errors}"
      if this_business.feature_enabled?(:move_emu_sso_configuration_page) && this_business.enterprise_managed_user_enabled?
        render "businesses/settings/identity_provider/edit_saml_configuration", locals: { params: params }
      else
        render "businesses/settings/security", locals: { params: params }
      end
    end
  end

  def save_saml_config
    new_setup = this_business.saml_provider.blank?
    provider = this_business.saml_provider || this_business.build_saml_provider
    provider.user_that_must_test_settings = current_user
    if new_setup && saml_params[:recovery_secret].present?
      provider.recovery_secret = saml_params[:recovery_secret]
      provider.recovery_used_bitfield = 0
      provider.recovery_codes_viewed = true
    end
    if new_setup && this_business.enterprise_managed_user_enabled?
      provider.scim_provisioning_state = :scim_provisioning_state_enabled
    end
    attributes = if GitHub.flipper[:saml_encrypted_assertions].enabled?(this_business)
      saml_params.slice \
        :sso_url, :issuer, :idp_certificate, :signature_method, :digest_method, \
        :encrypted_assertions, :encryption_method, :key_transport_method
    else
      saml_params.slice \
        :sso_url, :issuer, :idp_certificate, :signature_method, :digest_method
    end

    # Find the current SAML test settings to read the generate encryption key from and setup the
    # same key in production environment.
    if GitHub.flipper[:saml_encrypted_assertions].enabled?(this_business) && saml_params[:encrypted_assertions] == "1"
      test_settings = Business::SamlProviderTestSettings.most_recent_for(
        user: current_user,
        business: this_business,
      )
      attributes[:plaintext_key] = test_settings.plaintext_key
    end

    if provider.update(attributes)
      # Ensure that any possible cached setup flow values are cleared.
      saml_provider_setup_flow.clear_kv_values

      # Existing orgs with Team Sync enabled for their own provider will
      # misbehave (no UI to toggle Team Sync, membership losses upon team
      # mapping changes, etc.) when we add a provider to their Enterprise,
      # so we'd better disable on those orgs when adding a new config.
      #
      # (disabling removes mappings without touching memberships => 🏆)
      if new_setup
        TeamSync::Tenant.not_disabled.where(
          organization_id: this_business.organization_ids,
        ).each(&:disable)

        # We want to create a recovery session for first EMU admin owner so they continue to have access so they are not forced to re-authenticate with a recovery code
        if this_business.is_first_emu_owner?(user: current_user)
          set_emu_admin_recovery_session(this_business.reload, FIRST_EMU_OWNER_USER_SESSION_EXPIRY.from_now)
        end
      end
    else
      flash.now[:error] = "Your SAML provider settings could not be saved. #{provider.errors.full_messages.join(", ")}"
      if this_business.feature_enabled?(:move_emu_sso_configuration_page) && this_business.enterprise_managed_user_enabled?
        return render "businesses/settings/identity_provider/edit_saml_configuration", locals: { params: params }
      else
        return render "businesses/settings/security", locals: { params: params }
      end
    end

    saml_provider_setup_flow.clear_kv_values if saml_provider_setup_flow.pending?
    if this_business.feature_enabled?(:move_emu_sso_configuration_page) && this_business.enterprise_managed_user_enabled?
      if cookies.encrypted[:emu_onboarding].present?
        cookies.delete :emu_onboarding
        instrument_emu_omboarding_saml_complete
        redirect_to enterprise_getting_started_path(this_business)
      else
        redirect_to enterprise_single_sign_on_configuration_path(this_business)
      end
    else
      redirect_to \
        settings_security_enterprise_path(this_business),
        notice: "Your SAML provider settings were saved"
    end
  end

  def test_saml_config
    # Attempt to save the settings
    test_settings = Business::SamlProviderTestSettings.save_for(
      user: current_user,
      business: this_business,
      settings: saml_params,
    )

    if test_settings.valid?
      provider_url = service_provider_url

      options = if GitHub.flipper[:saml_encrypted_assertions].enabled?(this_business)
        {
          sp_url: provider_url,
          sso_url: test_settings.sso_url,
          assertion_consumer_service_url: saml_consume_url,
          destination: test_settings.sso_url,
          issuer: provider_url,
          signature_method: test_settings.signature_method,
          digest_method: test_settings.digest_method,
          encrypted_assertions: test_settings.encrypted_assertions,
          encryption_method: test_settings.encryption_method,
          key_transport_method: test_settings.key_transport_method,
          key: test_settings.key,
        }
      else
        {
          sp_url: provider_url,
          sso_url: test_settings.sso_url,
          assertion_consumer_service_url: saml_consume_url,
          destination: test_settings.sso_url,
          issuer: provider_url,
          signature_method: test_settings.signature_method,
          digest_method: test_settings.digest_method,
        }
      end

      # Initialize relay_state and authn_request with T.nilable types to maintain consistent typing across our different FF branches.
      # This ensures Sorbet recognizes that these variables can hold either nil or their respective types,
      # preventing type change errors when different FFs assign different types.
      relay_state = T.let(nil, T.nilable(String))
      authn_request = T.let(nil, T.nilable(Platform::Authentication::SAML::Authrequest))

      if this_business.feature_enabled?(:ruby_saml_bounty_testing)
        authn_request = Platform::Authentication::SAML::Authrequest.new
        relay_state = initiate_relay_state(authn_request)
        authn_request_url = initiate_candidate_logic(authn_request, relay_state, test_settings, provider_url, saml_consume_url)
      elsif GitHub.flipper[:saml_lib_replacement_project].enabled? && this_business.feature_enabled?(:saml_lib_replacement_business_provider_initiate)
        authn_request_url = science "validate_saml_lib_replacement_business_provider_initiate" do |e|
          e.use do
            temp_authn_request_url = Platform::Authentication::SamlAuthnRequestUrl.new(options)
            temp_authn_request_url.relay_state = initiate_relay_state(temp_authn_request_url.request)
            temp_authn_request_url
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
              provider_url,
              saml_consume_url,
              test_settings.signature_method,
              test_settings.digest_method,
            )
          end
          e.compare do |control, candidate|
            Platform::Authentication::SAML.initiate_match?(control, candidate)
          end
        end
      else
        authn_request_url = Platform::Authentication::SamlAuthnRequestUrl.new(options)
        authn_request_url.relay_state = initiate_relay_state(authn_request_url.request)
      end

      # We use "validate" as the cookie value in this action to allow the
      # consume endpoint to know that a user was trying to test their
      # provider settings after the SAML SSO post-back.
      cookies.encrypted[:saml_return_to] = "validate"
      cookies.encrypted[:saml_return_to_legacy] = "validate"

      allow_external_redirect_after_post(provider: test_settings)
      redirect_url = authn_request_url.to_s

      # If encrypted assertions are enabled, then present the user the encryption certificate before redirecting
      # them to the IdP.
      if GitHub.flipper[:saml_encrypted_assertions].enabled?(this_business) && options[:encrypted_assertions] && options[:key]
        render "businesses/identity_management/sso_download_encrypted_assertions_certificate",
          locals: { redirect_url: redirect_url, business_slug: this_business.slug },
          layout: "application"
      else
        render "businesses/identity_management/sso_meta_redirect",
          locals: { redirect_url: redirect_url },
          layout: "layouts/redirect"
      end
    else
      test_settings_errors = test_settings.errors.full_messages.join(", ")
      flash.now[:business_saml_test_result] = {
        status: Business::SamlProviderTestSettings::FAILURE,
        message: test_settings_errors,
      }
      flash.now[:error] = "Your SAML provider test settings are invalid"
      view_params = params.merge({
        saml_testing: {
          failure: true,
          message: test_settings.message,
          errors: test_settings.errors,
        },
      })
      if this_business.feature_enabled?(:move_emu_sso_configuration_page) && this_business.enterprise_managed_user_enabled?
        render "businesses/settings/identity_provider/edit_saml_configuration", locals: { params: view_params }
      else
        render "businesses/settings/security", locals: { params: view_params }
      end
    end
  end

  private def initiate_candidate_logic(authn_request, relay_state, test_settings, provider_url, saml_consume_url)
    Platform::Authentication::SAML.generate_authn_request_url(
      authn_request,
      relay_state,
      test_settings.sso_url,
      provider_url,
      saml_consume_url,
      test_settings.signature_method,
      test_settings.digest_method,
    )
  end

  def saml_provider_required
    render_404 unless this_business.saml_provider.present?
  end

  def initiate_relay_state(authn_request)
    relay_state = if GitHub.flipper[:redis_relay_state].enabled?(this_business)
      Platform::Authentication::SamlRedisRelayState.initiate(
        request_id: authn_request.id,
      )
    else
      Platform::Authentication::SamlRelayState.initiate(
        request_id: authn_request.id,
      )
    end

    # persist the relay state digest for future validation
    cookies.encrypted[:saml_csrf_token] = saml_csrf_cookie(relay_state.digest)
    cookies.encrypted[:saml_csrf_token_legacy] = saml_csrf_cookie((relay_state.digest))

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

  def first_emu_owner_required
    render_404 if current_user.is_emu_and_not_first_owner?
  end

  memoize def saml_provider_setup_flow
    SamlProviderSetupFlow.new(this_business)
  end

  def tmp_saml_provider
    saml_provider_setup_flow.tmp_provider
  end
  helper_method :tmp_saml_provider

  def not_oidc_business
    render_404 if this_business.oidc_enabled?
  end

  # We only want to instrument if this is the first instance of SCIM provisioning
  # for a trial EMU enterprise. The EMU onboarding wizard is active only for trial
  # EMU enterprises.
  def instrument_emu_omboarding_saml_complete
    return unless this_business.enterprise_managed_user_enabled?
    return unless this_business.trial?
    external_identities = ExternalIdentity
      .by_provider(this_business.external_provider)
      .not_disabled_and_deleted
      .limit(2)
    return if external_identities.count > 1

    GitHub.logger.info(
      "info.message": "EMU onboarding SAML complete",
      "gh.business_id": this_business.id,
      "gh.business_slug": this_business.slug,
    )
  end
end
