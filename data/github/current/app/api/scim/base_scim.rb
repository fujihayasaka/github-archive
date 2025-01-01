# typed: false
# frozen_string_literal: true

# Base SCIM api class implements methods for use in the scim user and group implementations
class Api::SCIM::BaseSCIM < Api::App
  include Api::SCIM::SCIMAuditDependency
  include Scientist

  # Set the rate limit family as SCIM_FAMILY, thus giving users a higher rate limit than the DEFAULT_FAMILY
  rate_limit_as Api::RateLimitConfiguration::SCIM_FAMILY

  AAD_USER_AGENT = "Microsoft Azure AD SCIM provisioning".downcase
  OKTA_USER_AGENT = "Okta SCIM client".downcase
  PING_FEDERATE_USER_AGENT = "Apache-HttpClient".downcase # PingFederate does not send a very specific user agent, but this should be fine

  SUPPORTED_USER_AGENTS = [AAD_USER_AGENT, OKTA_USER_AGENT, PING_FEDERATE_USER_AGENT].freeze

  # Public: A main execution method. Sets access control, checks if the scim was enabled for a target (uses
  #    scim_enabled? method that can be implemented by a controller for additional checks).  Finally it delegates
  #    to the correct method and processes the result.  The method process_scim_result must be implemented in a module
  #    responsible for different endpoint (users and groups).
  #
  # method           - the name of the method to execute implemented in the endpoint module
  # target           - target the the execution runs under, could be an organization or an enterprise
  # serialize_method - method used to serialize the returned results to json (can be setup in an override)
  # json_resource    - a resource name for extracting json (can be setup in an override)
  #
  # Returns scim result
  def execute(method:, target:, serialize_method: nil, json_resource: nil)
    set_provisioner(target)

    # setup call options the hash is used in the subsequent methods, to standardize access to parameters
    @call_options = {
      method: method,
      target: target,
      serialize_method: serialize_method || self.class::SERIALIZE_METHOD,
      json_resource: json_resource || self.class::JSON_RESOURCE,
    }

    # call appropriate method responsible for processing an endpoint and getting results
    results = send(@call_options[:method])

    # process the results returned from an endpoint method, this method is specific to each endpoint and
    # will be different between users and groups
    process_scim_result(results)
  end

  after ["*/Users/:external_identity_guid", "*/Groups/:external_identity_guid", "*"] do
    instrument_scim_api_request
  end

  protected

  # Protected: Check weather SCIM was enabled on an enterprise
  #
  # enterprise          - Enterprise to check
  #
  # Returns Boolean
  def enterprise_scim_enabled?(enterprise)
    return false unless enterprise.external_provider_enabled?
    return true if enterprise.enterprise_managed_user_enabled? && enterprise.oidc_enabled?
    return true if enterprise.enterprise_managed_user_enabled? && enterprise.saml_provider.scim_provisioning_state_enabled?
    return true if enterprise.enterprise_server_scim_enabled?
    return true if enterprise.feature_enabled?(:enterprise_idp_provisioning)
    false
  end

  # Protected: If the enterprise is EMU or GHES enabled, validates the SCIM user agent and blocks unsupported ones.
  #
  # enterprise          - Enterprise to check
  #
  # Returns nothing or halts request and returns error
  def block_unsupported_scim_user_agents(enterprise)
    return unless enterprise.enterprise_managed_user_enabled? || GitHub.single_business_environment?

    user_agent = request.user_agent&.downcase

    if user_agent.blank?
      return deliver_error!(403, message: "User-Agent is required for #{enterprise.enterprise_managed_user_enabled? ? "Enterprise Managed User" : "Enterprise Server"} enabled SCIM Provisioning")
    end

    if enterprise.feature_enabled?(:block_scim_writes)
      return deliver_error!(403, message: "SCIM writes have been disabled for this Enterprise, please reach out to your Account Manager for assistance")
    end

    block_mismatch_providers(enterprise, user_agent)

    return if enterprise.eligible_for_open_scim? && enterprise.open_scim_enabled?

    # check if the user_agent is AAD, Okta, or PingFederate
    # Okta and Ping appear to version their SCIM Client and sends that in the user_agent string so we can't match directly
    # AAD appers to just use a static string
    if !SUPPORTED_USER_AGENTS.any? { |ua| user_agent.include?(ua) }
      deliver_error!(403, message: "Enterprise Managed User enabled Enterprises must use Azure AD, Okta, or Ping Federate for SCIM Provisioning")
    end
  end

  private

  # Private: Checks if SSO and SCIM providers for the given enterprise match. If they don't match, it logs the mismatch and may block the request.
  #
  # Currently, we only block:
  # - Okta SSO with Azure SCIM
  # - Azure SSO with Okta SCIM
  #
  # enterprise  - Enterprise to check.
  # user_agent  - The User Agent string, used for logging.
  #
  # Returns nothing, but may halt the execution and deliver an error if the SSO and SCIM providers are mismatched in a disallowed way.
  def block_mismatch_providers(enterprise, user_agent)
    return unless enterprise.external_provider.present?

    sso_provider_type = enterprise.external_provider.find_provider_type
    scim_provider_type = Business.scim_provider_type
    product = enterprise.enterprise_managed_user_enabled? ? "Enterprise Managed User" : "GitHub Enterprise Server"

    return if sso_provider_type == scim_provider_type
    # We can't always identify Ping Federate from the issuer url so we classify it as "unknown" and don't log it if it's Ping Federate User Agent
    return if sso_provider_type == :unknown && scim_provider_type == :ping_federate

    GitHub.logger.info(
      "info.message" => "Mismatched SCIM & SSO Providers",
      "gh.business.id" => enterprise.id,
      "gh.business.slug" => enterprise.slug,
      "gh.business.sso.provider_type" => sso_provider_type,
      "gh.user_agent" => user_agent
    )

    # long-lived FF to selectively allow customers with specific sso and scim providers combination, we currently only regulate Okta and Azure AD
    return if enterprise.feature_enabled?(:allow_mix_and_match_partner_idps)
    if sso_provider_type == :okta && scim_provider_type == :azure_ad
      deliver_error!(403, message: "#{product} enabled Enterprises cannot have Okta for SSO and Microsoft Entra ID for SCIM Provisioning at the same time",
        documentation_url: "#{GitHub.help_url}/admin/identity-and-access-management/provisioning-user-accounts-for-enterprise-managed-users/provisioning-users-with-scim-using-the-rest-api")
    elsif sso_provider_type == :azure_ad && scim_provider_type == :okta
      deliver_error!(403, message: "#{product} enabled Enterprises cannot have Microsoft Entra ID for SSO and Okta for SCIM Provisioning at the same time",
        documentation_url: "#{GitHub.help_url}/admin/identity-and-access-management/provisioning-user-accounts-for-enterprise-managed-users/provisioning-users-with-scim-using-the-rest-api")
    end
  end
end
