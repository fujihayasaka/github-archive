# typed: true
# frozen_string_literal: true

require "oidc"

class Businesses::OIDCProviderController < Businesses::BusinessController
  include BusinessesHelper
  include OIDCDependency

  before_action :business_oidc_required
  before_action :read_enterprise_sso_required, only: %w(recovery_codes download_recovery_codes print_recovery_codes)
  before_action :write_enterprise_sso_required, only: %w(create delete regenerate_recovery_codes)
  before_action :first_emu_owner_required, only: %w(delete create)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    only: [:print_recovery_codes]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:recovery_codes]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:recovery_codes],
    optional: true

  OIDC_ENABLE_INSTRUMENTATION_KEY  = "business.enable_oidc"
  OIDC_DISABLE_INSTRUMENTATION_KEY = "business.disable_oidc"

  def create
    if params[:recovery_codes_viewed]
      cached_setup_values = get_cached_setup_values(this_business)
      return render_404 unless cached_setup_values

      cached_setup_values = JSON.parse(cached_setup_values)

      provider = Business::OIDCProvider.new(
        business: this_business,
        oidc_provider: params[:oidc_provider_key],
        tenant_id: cached_setup_values["tenant_id"],
        secret: cached_setup_values["secret"],
        recovery_secret: cached_setup_values["recovery_secret"],
        recovery_used_bitfield: 0,
        recovery_codes_viewed: true,
        migrate_to_oidc: cached_setup_values["migrate_to_oidc"],
      )

      unless provider.save
        flash[:error] = provider.errors.full_messages.join(", ")
        return render_404
      end

      instrument_oidc_sso(OIDC_ENABLE_INSTRUMENTATION_KEY)

      if this_business.eligible_for_ip_allowlist_configuration? && this_business.ip_allowlist_enabled?
        this_business.update_ip_allowlist_configuration(
          actor: current_user,
          config_value: Configurable::IpAllowlistConfiguration::GITHUB)
      end

      # if provider was Saved successfully and we are migrating from SAML to OIDC provider initiate a migration job here
      if cached_setup_values["migrate_to_oidc"] && this_business.saml_provider.present?
        MigrateBusinessProviderJob.perform_later(business_id: this_business.id, saml_provider_id: this_business.saml_provider.id, oidc_provider_id: provider.id)
      end

      # We want to create a recovery session for first EMU admin owner so they continue to have access so they are not forced to re-authenticate with a recovery code
      if this_business.is_first_emu_owner?(user: current_user)
        set_emu_admin_recovery_session(this_business.reload, FIRST_EMU_OWNER_USER_SESSION_EXPIRY.from_now)
      end

      clean_up_cached_setup_values(this_business)
    else
      params[:oidc] ||= {}
      if this_business.oidc_provider.blank? && params[:oidc][:oidc_provider].present?
        render "businesses/identity_management/sso_meta_redirect", locals: { redirect_url: oidc_authorize_url }, layout: "layouts/redirect"
        return
      end
    end

    if cookies.encrypted[:emu_onboarding].present?
      cookies.delete :emu_onboarding
      instrument_emu_omboarding_oidc_complete
      redirect_to enterprise_getting_started_path(this_business)
    else
      redirect_to enterprise_single_sign_on_configuration_path(this_business)
    end
  end

  def delete # rubocop:todo GitHub/UseRestfulActions
    this_business.oidc_provider&.destroy
    instrument_oidc_sso(OIDC_DISABLE_INSTRUMENTATION_KEY)
    flash[:notice] = "OIDC single sign-on is disabled"
    redirect_to enterprise_single_sign_on_configuration_path(this_business)
  end

  def recovery_codes # rubocop:todo GitHub/UseRestfulActions
    if this_business.feature_enabled?(:oidc_recovery_code_in_url)
      if this_business.oidc_provider.blank?
        new_setup_recovery_codes = get_recovery_codes(this_business)
      end
    else
      new_setup_recovery_codes = params[:new_setup_recovery_codes]
    end

    render "businesses/oidc_provider/recovery_codes", locals: {
      business: this_business,
      oidc_provider_key: params[:oidc_provider_key],
      new_setup_recovery_codes: new_setup_recovery_codes
    }

    this_business.instrument(:recovery_codes_viewed)
  end

  def download_recovery_codes # rubocop:todo GitHub/UseRestfulActions
    codes = if this_business.oidc_provider.blank?
      get_recovery_codes(this_business)
    else
      this_business.oidc_provider.formatted_recovery_codes
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
        if this_business.oidc_provider.blank?
          new_setup_recovery_codes = get_recovery_codes(this_business)
        end

        render "businesses/print_recovery_codes", layout: "layouts/popup", locals: {
          new_setup_recovery_codes: new_setup_recovery_codes.presence
        }
      end
    end

    this_business.instrument(:recovery_codes_printed)
  end

  def regenerate_recovery_codes # rubocop:todo GitHub/UseRestfulActions
    provider = this_business.oidc_provider
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
    redirect_to settings_oidc_provider_recovery_codes_enterprise_path(this_business)
  end

  private

  def oidc_provider_required
    render_404 unless this_business.oidc_provider.present?
  end

  def first_emu_owner_required
    render_404 if current_user.is_emu_and_not_first_owner?
  end

  def get_cached_setup_values(business)
    ExternalIdentities::KV.get("oidc_provider_setup:#{business.id}").value!
  end

  def get_recovery_codes(business)
    cached_setup_values = get_cached_setup_values(business)
    if cached_setup_values
      JSON.parse(cached_setup_values)["recovery_codes"]
    else
      nil
    end
  end

  def clean_up_cached_setup_values(business)
    ExternalIdentities::KV.del("oidc_provider_setup:#{business.id}")
  end

  def instrument_oidc_sso(name)
    payload = {
      actor: current_user,
      business: this_business
    }

    GitHub.instrument(name, payload)
  end

  # We only want to instrument if this is the first instance of SCIM provisioning
  # for a trial EMU enterprise. The EMU onboarding wizard is active only for trial
  # EMU enterprises.
  def instrument_emu_omboarding_oidc_complete
    return unless this_business.enterprise_managed_user_enabled?
    return unless this_business.trial?

    external_identities = ExternalIdentity.by_provider(this_business.external_provider).is_active.limit(2)

    return if external_identities.count > 1

    GitHub.logger.info(
      "info.message": "EMU onboarding OIDC complete",
      "gh.business_id": this_business.id,
      "gh.business_slug": this_business.slug,
    )
  end
end
