# typed: true
# frozen_string_literal: true

class Businesses::SCIMConfigurationController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :sudo_filter
  before_action :enterprise_required

  SCIM_ENABLED_RESPONSE = "SCIM enabled.".freeze
  SCIM_DISABLED_RESPONSE = "SCIM disabled.".freeze
  UNABLE_TO_ENABLE_SCIM_RESPONSE = "Unable to enable SCIM".freeze
  UNABLE_TO_DISABLE_SCIM_RESPONSE = "Unable to disable SCIM".freeze

  def update
    scim_configuration = params[:scim_configuration]&.to_s

    if scim_configuration == "on"
      handle_scim_enablement
    else
      handle_scim_disablement
    end

    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def handle_scim_enablement
    Business.transaction do
      saml_provider = ensure_saml_provider

      if saml_provider && saml_provider.errors.empty?
        begin
          this_business.enable_open_scim(actor: current_user)
          flash[:notice] = SCIM_ENABLED_RESPONSE
        rescue Configurable::OpenSCIM::OpenSCIMError
          flash[:error] = UNABLE_TO_ENABLE_SCIM_RESPONSE
          raise ActiveRecord::Rollback
        end
      else
        flash[:error] = UNABLE_TO_ENABLE_SCIM_RESPONSE
      end
    end
  end

  def handle_scim_disablement
    Business.transaction do
      this_business.disable_open_scim(actor: current_user)
      saml_provider = destroy_saml_provider
      if saml_provider
        flash[:notice] = SCIM_DISABLED_RESPONSE
      else
        flash[:error] = UNABLE_TO_DISABLE_SCIM_RESPONSE
        raise ActiveRecord::Rollback
      end
    end
  rescue Configurable::OpenSCIM::OpenSCIMError
    flash[:error] = UNABLE_TO_DISABLE_SCIM_RESPONSE
  end

  def ensure_saml_provider
    return unless ensure_saml_provider_requirement_met?

    # Business::SamlProvider already exists
    return GitHub.global_business.saml_provider if GitHub.global_business.saml_sso_enabled?

    # Create a new Business::SamlProvider
    create_saml_provider
  end

  def ensure_saml_provider_requirement_met?
    return false unless GitHub.enterprise?
    return false unless GitHub.global_business
    return false unless GitHub.auth.saml?

    true
  end

  def create_saml_provider
    provider = GitHub.global_business.build_saml_provider
    provider.sso_url = GitHub.saml_sso_url
    provider.issuer = GitHub.saml_issuer
    provider.idp_certificate = File.read(GitHub.saml_certificate_file)
    provider.scim_provisioning_state = :scim_provisioning_state_enabled
    provider.save

    provider
  end

  def destroy_saml_provider
    return unless destroy_saml_provider_requirement_met?

    GitHub.global_business.saml_provider.destroy
  end

  def destroy_saml_provider_requirement_met?
    return false unless GitHub.enterprise?
    return false unless GitHub.global_business
    return false unless GitHub.global_business.saml_sso_enabled?

    true
  end
end
