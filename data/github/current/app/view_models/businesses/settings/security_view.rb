# typed: true
# frozen_string_literal: true

class Businesses::Settings::SecurityView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include EnterpriseManagedUsersHelper

  attr_reader :business, :params

  def initialize(**args)
    super(args)

    @business = args[:business]
    @params = args[:params] || {}
    @current_user = args[:current_user]
  end

  def two_factor_requirement_form_disabled?
    !GitHub.auth.two_factor_org_requirement_allowed? ||
      (!two_factor_requirement_enabled? && blocking_orgs_count > 0)
  end

  def disabled_form_reason
    if !GitHub.auth.two_factor_authentication_enabled?
      "Built-in two-factor authentication is disabled on your instance."
    elsif GitHub.auth.builtin_auth_fallback? && !GitHub.auth.two_factor_org_requirement_allowed?
      "Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed."
    elsif !current_user.two_factor_authentication_enabled?
      link = helpers.link_to("enabled on your personal account", urls.settings_security_path, class: "Link--inTextBlock")
      helpers.safe_join(["Two-factor authentication must be ", link, " to require it for the enterprise."])
    elsif blocking_orgs_count > 0
      count = blocking_orgs_count
      "Enforcing two-factor authentication would remove all admins from the #{blocking_orgs_names} #{"organization".pluralize(count)}."
    end
  end

  def builtin_auth_fallback?
    return false unless GitHub.enterprise?
    GitHub.auth.builtin_auth_fallback?
  end

  def blocking_orgs
    @blocking_orgs ||= organizations_blocking_enabling_two_factor.limit(10)
  end

  def blocking_orgs_count
    @blocking_orgs_count ||= organizations_blocking_enabling_two_factor.count
  end

  def blocking_orgs_names
    names = blocking_orgs.flat_map(&:name)
    extra = blocking_orgs_count - names.size
    names << "and #{extra} more" if extra > 0
    message = names.to_sentence
  end

  def disable_submit_button?
    two_factor_requirement_form_disabled? ||
      business.updating_two_factor_requirement?
  end

  def two_factor_requirement_needs_confirmation?
    business.can_disallow_two_factor_methods? || (
      !two_factor_requirement_enabled? &&
      business.affiliated_users_with_two_factor_disabled_exist?
    )
  end

  def two_factor_requirement_enabled?
    business.two_factor_requirement_enabled?
  end

  def two_factor_secure_methods_required?
    business.insecure_two_factor_methods_disallowed?
  end

  def referrer_override_enabled?
    business.referrer_override_enabled?
  end

  def saml_provider_params
    @saml_provider_params ||= params.fetch(:saml, {})
  end

  def oidc_provider_params
    @oidc_provider_params ||= params.fetch(:oidc, {})
  end

  def saml_testing_params
    @saml_testing_params ||= params.fetch(:saml_testing, {})
  end

  def current_external_identity
    @current_external_identity ||= params.fetch(:current_external_identity, nil)
  end

  def saml_settings_saved?
    return false if GitHub.enterprise? && GitHub.auth.saml?
    business.saml_provider&.sso_url&.present? &&
      business.saml_provider&.idp_certificate&.present?
  end

  def oidc_settings_saved?
    business.oidc_provider.present?
  end

  def show_saml_settings?
    return true if GitHub.enterprise? && GitHub.auth.saml?
    saml_settings_saved? || saml_provider_params.present?
  end

  def show_oidc_settings?
    return false unless business_emu_configured?
    oidc_settings_saved? || oidc_provider_params.present?
  end

  def tenant_id
    business&.oidc_provider&.tenant_id&.to_s
  end

  def saml_sso_url
    saml_provider_params[:sso_url] || business.saml_provider&.sso_url&.to_s || GitHub.saml_sso_url
  end

  def issuer
    saml_provider_params[:issuer] || business.saml_provider&.issuer || GitHub.saml_issuer
  end

  def idp_certificate
    return File.read(GitHub.saml_certificate_file) if GitHub.enterprise? && GitHub.auth.saml?
    saml_provider_params[:idp_certificate] || business.saml_provider&.idp_certificate&.to_s
  end

  def encrypted_assertions_enabled?
    return false unless GitHub.flipper[:saml_encrypted_assertions].enabled?(business)
    saml_provider_params[:encrypted_assertions] || business.saml_provider&.encrypted_assertions
  end

  def okta_team_sync?
    provider_type&.to_sym == :okta
  end

  def saml_testing?
    !!params[:test_settings]
  end

  def saml_test_failure?
    saml_testing? && saml_testing_params[:failure]
  end

  def saml_test_success?
    saml_testing? && saml_testing_params[:success]
  end

  def saml_test_errors
    return unless saml_testing?

    saml_testing_params[:message] || "invalid settings"
  end

  def saml_testing_input_fields_errors
    return unless saml_testing?

    @saml_testing_input_fields_errors ||= saml_testing_params[:errors]
  end

  def saml_testing_field_error_message(field)
    return unless saml_testing? && saml_testing_input_fields_errors&.include?(field)

    saml_testing_input_fields_errors.full_messages_for(field).join(", ")
  end

  def saml_sso_url_error
    saml_testing_field_error_message(:sso_url)
  end

  def issuer_error
    saml_testing_field_error_message(:issuer)
  end

  def idp_certificate_error
    saml_testing_field_error_message(:idp_certificate)
  end

  def tenant_id_error
    return unless business.oidc_provider.present?
    return if business.oidc_provider.valid?
    business.oidc_provider.errors.full_messages_for(:tenant_id).join(", ")
  end

  DEFAULT_SIGNATURE_METHOD = SamlProviderAlgorithms::DEFAULT_SIGNATURE_METHOD
  SIGNATURE_METHOD_OPTIONS = {
    "RSA-SHA1": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha1",
    "RSA-SHA256": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
    "RSA-SHA384": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384",
    "RSA-SHA512": "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512",
  }

  def signature_method
    saml_provider_params[:signature_method] ||
      business.saml_provider&.signature_method&.to_s ||
      GitHub.saml_signature_method ||
      DEFAULT_SIGNATURE_METHOD
  end

  def saml_signature_method
    SIGNATURE_METHOD_OPTIONS.invert[signature_method]
  end

  def saml_signature_method_options
    SIGNATURE_METHOD_OPTIONS
  end

  DEFAULT_DIGEST_METHOD = SamlProviderAlgorithms::DEFAULT_DIGEST_METHOD
  DIGEST_METHOD_OPTIONS = {
    "SHA1": "http://www.w3.org/2000/09/xmldsig#sha1",
    "SHA256": "http://www.w3.org/2001/04/xmlenc#sha256",
    "SHA384": "http://www.w3.org/2001/04/xmlenc#sha384",
    "SHA512": "http://www.w3.org/2001/04/xmlenc#sha512",
  }

  def digest_method
    saml_provider_params[:digest_method] ||
      business.saml_provider&.digest_method&.to_s ||
      GitHub.saml_digest_method ||
      DEFAULT_DIGEST_METHOD
  end

  def saml_digest_method
    DIGEST_METHOD_OPTIONS.invert[digest_method]
  end

  def saml_digest_method_options
    DIGEST_METHOD_OPTIONS
  end

  DEFAULT_ENCRYPTION_METHOD = SamlProviderAlgorithms::DEFAULT_ENCRYPTION_METHOD
  ENCRYPTION_METHOD_OPTIONS = {
    "AES-128-CBC" => "http://www.w3.org/2001/04/xmlenc#aes128-cbc",
    "AES-192-CBC" => "http://www.w3.org/2001/04/xmlenc#aes192-cbc",
    "AES-256-CBC" => "http://www.w3.org/2001/04/xmlenc#aes256-cbc",
  }

  def encryption_method
    saml_provider_params[:encryption_method] ||
      business.saml_provider&.encryption_method&.to_s ||
      DEFAULT_ENCRYPTION_METHOD
  end

  def saml_encryption_method_options
    ENCRYPTION_METHOD_OPTIONS
  end

  DEFAULT_KEY_TRANSPORT_METHOD = SamlProviderAlgorithms::DEFAULT_KEY_TRANSPORT_METHOD
  KEY_TRANSPORT_METHOD_OPTIONS = {
    "RSA-OAEP" => "http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p",
  }

  def key_transport_method
    saml_provider_params[:key_transport_method] ||
      business.saml_provider&.key_transport_method&.to_s ||
      DEFAULT_KEY_TRANSPORT_METHOD
  end

  def saml_key_transport_method_options
    KEY_TRANSPORT_METHOD_OPTIONS
  end

  def saml_identity_provider_setting_organizations_business_path
    urls.enterprise_organizations_setting_path(business, "saml_identity_provider")
  end

  def show_ssh_cas?
    GitHub.ssh_enabled?
  end

  def show_ip_allowlist?
    GitHub.ip_allowlists_available?
  end

  def business_emu_configured?
    business&.enterprise_managed_user_enabled?
  end

  def show_team_sync_settings?
    saml_settings_saved? && !business_emu_configured?
  end

  def supported_team_sync_provider?
    team_sync_provider_candidate&.supported_for_business?(business)
  end

  def disallow_team_sync_setup?
    current_external_identity.nil?
  end

  def enable_team_sync_settings?
    saml_settings_saved? &&
    supported_team_sync_provider?
  end

  # TODO : Get teams in a business
  def team_sync_status
    "Teams managed in #{team_sync_provider_type_label}."
  end

  def team_sync_activity_link
    query = { q: "actor:github-team-synchronization[bot] action:team.add_member action:team.remove_member" }
    helpers.link_to("View activity", urls.settings_audit_log_enterprise_path(business, query))
  end

  IDENTITY_PROVIDER_OPTIONS = {
    "unknown" => "Unknown",
    "azuread" => "Entra ID",
    "okta" => "Okta",
  }

  def show_enable_team_sync_button?
    ::TeamSync::SetupFlow::STARTING_STATES.include?(team_sync_setup_flow.status) ||
      team_sync_setup_flow.status.nil?
  end

  def show_team_sync_assignment_review_available?
    ::TeamSync::SetupFlow::APPROVAL_STATE == team_sync_setup_flow.status
  end

  def team_sync_enabled?
    team_sync_setup_flow.tenant.team_sync_enabled?
  end

  def team_sync_provider_type_label
    IDENTITY_PROVIDER_OPTIONS[provider_type]
  end

  def team_sync_provider_id
    team_sync_setup_flow.provider_id
  end

  def show_orgs_with_saml_configured?
    return false if GitHub.enterprise? && GitHub.auth.saml?
    !current_user.is_enterprise_managed?
  end

  def sso_configured_checkbox_disabled?
    current_user.is_emu_and_not_first_owner?
  end

  def require_saml_sso_label
    if business.removing_external_provider?
      if business.removing_external_provider_type == Business::ExternalProviderDependency::REMOVE_SAML_PROVIDER_TYPE
        "Previous SAML provider is being removed"
      else
        "Previous OIDC provider is being removed"
      end
    elsif builtin_auth_fallback?
      "Can use SAML authentication"
    else
      "Require SAML authentication"
    end
  end

  def saml_sso_configured_checkbox_disabled?
    return true if GitHub.enterprise? && GitHub.auth.saml?
    return true if sso_configured_checkbox_disabled?
    business.oidc_provider.present? || business.removing_external_provider?
  end

  def require_oidc_sso_label
    if business.removing_external_provider?
      if business.removing_external_provider_type == "Business::SamlProvider"
        "Previous SAML provider is being removed"
      else
        "Previous OIDC provider is being removed"
      end
    else
      "Require OIDC single sign-on"
    end
  end

  def saml_oidc_migration_enabled?
    business.enterprise_managed_user_and_saml_sso_enabled? && !saml_sso_configured_checkbox_disabled?
  end

  def oidc_sso_configured_checkbox_disabled?
    return true if sso_configured_checkbox_disabled?
    business.saml_provider.present? || business.removing_external_provider?
  end

  def default_ip_allowlist_configuration_button_text
    default_ip_allowlist_configuration_selected_option[:heading]
  end

  def default_ip_allowlist_configuration_selected_option
    default_ip_allowlist_configuration_select_list.find { |s| s[:selected] }
  end

  def default_ip_allowlist_configuration_select_list
    return @select_list if defined? @select_list
    @select_list = [
      {
        heading: "Disabled",
        description: "Disable IP allow list restrictions in the enterprise",
        value: Businesses::IpAllowlistConfigurationController::DISABLED_VALUE,
        selected: business.disabled_ip_allowlist_configuration?
      },
      {
        heading: "Identity Provider",
        description: "Enable Identity Provider based IP allow list restrictions in the enterprise",
        value: Businesses::IpAllowlistConfigurationController::IDP_VALUE,
        selected: business.idp_based_ip_allowlist_configuration?,
      },
      {
        heading: "GitHub",
        description: "Enable GitHub based IP allow list restrictions in the enterprise",
        value: Businesses::IpAllowlistConfigurationController::GITHUB_VALUE,
        selected: business.github_based_ip_allowlist_configuration?,
      },
    ]
  end

  def current_ip_allowlist_configuration
    default_ip_allowlist_configuration_select_list.find { |item| item[:selected] }
  end

  def idp_organizations_github_allowlist_text
    orgs_count = orgs_ip_allowlist_enabled.count
    is_plural = orgs_count > 1
    organization_plural =  "organization".pluralize(orgs_count)
    list_plural = "list".pluralize(orgs_count)

    "#{orgs_count} #{organization_plural} currently #{is_plural ? "have" : "has"}"\
      " GitHub-native IP allow #{list_plural} enabled. Setting the IP allow list"\
      " configuration to use your identity provider's policies will disable the"\
      " GitHub-native IP allow #{list_plural} in #{is_plural ? "these" : "this"} #{organization_plural}."
  end

  # Public: Method to check if the changes to SAML SSO configuration need to be disabled.
  #    It is very important that any changes to SSO are done through a delete of an existing provider
  #    and addition of a new one.  By updating the SSO settings customers were running into situations
  #    where single user had multiple external identity records which is not allowed and were experiencing
  #    failures.  This fix is important in case of moving from one tenant to another or switching IdP providers.
  #
  # Returns Boolean
  def saml_sso_configuration_changes_readonly?
    return true if GitHub.enterprise? && GitHub.auth.saml?
    business.enterprise_managed_user_enabled? && business.saml_provider.present?
  end

  def saml_sso_configuration_readonly?
    return true if GitHub.enterprise? && GitHub.auth.saml?
    false
  end

  def sso_url
    if business.feature_enabled?(:use_multi_tenant_host_name_check)
      urls.business_idm_sso_enterprise_url(business, protocol: GitHub.scheme, host: GitHub.host_name_with_tenant)
    else
      urls.business_idm_sso_enterprise_url(business, protocol: GitHub.scheme, host: GitHub.host_name)
    end
  end

  def sso_path
    urls.business_idm_sso_enterprise_path(business.slug)
  end

  def saml_consume_url
    if GitHub.enterprise?
      urls.saml_consume_url(protocol: GitHub.scheme, host: GitHub.host_name)
    else
      if business.feature_enabled?(:use_multi_tenant_host_name_check)
        urls.idm_saml_consume_enterprise_url(business, protocol: GitHub.scheme, host: GitHub.host_name_with_tenant)
      else
        urls.idm_saml_consume_enterprise_url(business, protocol: GitHub.scheme, host: GitHub.host_name)
      end
    end
  end

  def saml_consume_path
    if GitHub.enterprise?
      urls.saml_consume_path
    else
      urls.idm_saml_consume_enterprise_path(business.slug)
    end
  end

  def supported_idps
    if business_emu_configured?
      "Azure and Okta"
    else
      "Azure, Okta, OneLogin, Ping Identity, or a custom SAML 2.0 provider"
    end
  end

  def show_sso_settings?
    business.enterprise_managed_user_enabled?
  end

  def show_proxy_settings?
    business.feature_enabled?(:show_proxy_header_info_to_customer) && business.proxy_security_header_enabled?
  end

  def proxy_header_value
    "sec-GitHub-allowed-enterprise: #{business.id}"
  end

  def show_open_scim_configuration?
    return false if GitHub.enterprise?
    return false unless business.present?
    return false unless business.eligible_for_open_scim?

    true
  end

  def show_scim_configuration?
    return false unless GitHub.enterprise?
    return false unless GitHub.global_business
    return false unless GitHub.auth.saml?

    true
  end

  def orgs_ip_allowlist_enabled
    @orgs_ip_allowlist_enabled ||= business.organizations.select(&:ip_allowlist_enabled_local?)
  end

  def show_disable_business_github_native_ip_allowlist_warning?(config_value)
    config_value == Businesses::IpAllowlistConfigurationController::DISABLED_VALUE &&
      business.ip_allowlist_enabled?
  end

  def show_disable_business_and_orgs_github_native_ip_allowlist_warning?(config_value)
    config_value == Businesses::IpAllowlistConfigurationController::IDP_VALUE &&
      business.ip_allowlist_enabled?
  end

  def configure_new_sso_disabled?
    business.removing_external_provider?
  end

  def external_provider_being_removed_text
    provider_type = if business.removing_external_provider_type == Business::ExternalProviderDependency::REMOVE_SAML_PROVIDER_TYPE
      "SAML"
    else
      "OIDC"
    end

    "Previous #{provider_type} provider is being removed"
  end

  def show_saml_configuration?
    business.saml_sso_enabled? && !business.removing_external_provider?
  end

  def show_oidc_configuration?
    business.oidc_enabled? && !business.removing_external_provider?
  end

  def show_configure_new_sso?
    !business.external_provider_enabled? || business.removing_external_provider?
  end

  def show_saml_disable_form_input_section?
    saml_sso_configuration_changes_readonly? && !GitHub.enterprise?
  end

  private

  # This is the potential team sync provider, based on the SAML issuer
  def team_sync_provider_candidate
    @team_sync_provider_candidate ||= ::TeamSync::Provider.detect(issuer: issuer)
  end

  # Derive type from SAML issuer (instead of tenants that may have
  # been created from older SAML configurations).
  def provider_type
    team_sync_provider_candidate&.type
  end

  def team_sync_setup_flow
    ::TeamSync::SetupFlow.new(business: business, actor: @current_user)
  end

  def organizations_blocking_enabling_two_factor
    business
      .organizations_can_enable_two_factor_requirement(false)
      .order("login ASC")
  end
end
