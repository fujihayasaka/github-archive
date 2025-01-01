# typed: true
# frozen_string_literal: true

class Stafftools::Users::EmuDeprovisioningController < StafftoolsController
  before_action :ensure_enterprise_managed_user

  # Suspend the user, obfuscate their login, and disable their external identity.
  #
  # This is only used when deprovisioning via SCIM has failed and the IdP is out of sync with dotcom.
  def create
    # If the SCIM provider is Okta, soft deprovisioning will perform GDPR cleanup
    GitHub.context.push(user_agent: Api::SCIM::BaseSCIM::OKTA_USER_AGENT) if params[:okta_scim]

    external_identity = this_user.external_identities.first
    display_login = this_user.display_login

    scim_user_data = external_identity.scim_user_data
    # Setting the active attribute to false will soft deprovision the user
    scim_user_data.replace "active", "false"

    # This is the same action performed on a PATCH request to /scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid
    result = Platform::Provisioning::EnterpriseManagedIdentityProvisioner.update \
      target: this_user.enterprise_managed_business,
      user_data: scim_user_data,
      mapper: Platform::Provisioning::ScimMapper,
      identity: external_identity,
      actor_id: current_user.id

    if result.success?
      flash[:notice] = "User #{display_login} has been soft deprovisioned. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}"
    else
      GitHub.logger.error(
        "Error while soft deprovisioning user from stafftools",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.user.id" => this_user.id,
        "gh.user.login" => this_user.login,
        "gh.business.id" => this_user.enterprise_managed_business&.id,
        "exception.type" => result.errors.first.reason,
        "exception.message" => result.error_messages.join(", "),
      )
      flash[:error] = "There was an error soft deprovisioning user #{display_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}. #{result.error_messages.join(", ")}"
    end

    redirect_to stafftools_enterprise_suspended_members_path(this_user.enterprise_managed_business)
  end

  # Hard deprovision the user. This action:
  # - Permanently suspends the EMU.
  # - Obfuscates their login and profile email.
  # - Disables their linked external identity.
  # - Sets the display name to an empty string.
  # - Deletes the user's external identity attributes.
  # - Deletes the emails, avatar, PATs, SSH keys, OAuth authorizations credentials, GPG keys, and SAML mappings for the user.
  #
  # This is only used when hard deprovisioning via SCIM has failed and the IdP is out of sync with dotcom.
  def destroy
    external_identity = this_user.external_identities.first
    display_login = this_user.display_login

    scim_user_data = external_identity.scim_user_data
    scim_user_data.replace "active", "false"

    # This is the same action performed on a DELETE request to /scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid
    result = Platform::Provisioning::EnterpriseManagedIdentityProvisioner.deprovision \
      target: this_user.enterprise_managed_business,
      user_data: scim_user_data,
      mapper: Platform::Provisioning::ScimMapper,
      identity: external_identity,
      actor_id: current_user.id

    if result.success?
      flash[:notice] = "User #{display_login} has been hard deprovisioned. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}"
    else
      GitHub.logger.error(
        "Error while hard deprovisioning user from stafftools",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.user.id" => this_user.id,
        "gh.user.login" => this_user.login,
        "gh.business.id" => this_user.enterprise_managed_business&.id,
        "exception.type" => result.errors.first.reason,
        "exception.message" => result.error_messages.join(", "),
      )
      flash[:error] = "There was an error hard deprovisioning user #{display_login}. Logs can be queried in Splunk with the following user ID: \"gh.user.id\"=#{this_user.id}. #{result.error_messages.join(", ")}"
    end

    redirect_to stafftools_enterprise_suspended_members_path(this_user.enterprise_managed_business)
  end
end
