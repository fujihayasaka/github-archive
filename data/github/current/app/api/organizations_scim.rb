# typed: false
# frozen_string_literal: true

class Api::OrganizationsScim < Api::App
  include ReceiveSchemaWithOpenApi

  include Api::App::SCIMHelpers

  allow_media SCIM::CONTENT_TYPE

  # Bypass IP allow list enforcement for calls to these endpoints since we do
  # not require an allow list to include the IP addresses of an IdP.
  def ip_allowlist_enforceable
    :no
  end

  # GET a list of users
  get "/scim/v2/organizations/:organization_id/Users", operation_id: "scim/list-provisioned-identities" do
    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization)
    deliver_error!(error_code, message: error_msg) if error_code

    control_access :org_scim_reader,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    identities = filter_identities(organization)

    results = paginated_results(identities)

    deliver_scim(:scim_identities_hash, results)
  end

  def filter_identities(organization)
    identities = organization.saml_provider.external_identities.provisioned_by(:scim).with_scim_preloads

    if params[:filter]
      identities = begin
          identities.scim_filter(params[:filter])
        rescue SCIM::Filter::InvalidFilterError => e
          # https://tools.ietf.org/html/rfc7644#section-3.12
          deliver_scim_error!(400, scim_type: "invalidFilter", detail: e.message, result: nil)
        end
    end

    identities
  end

  # get details about a specific user
  get "/scim/v2/organizations/:organization_id/Users/:external_identity_guid", operation_id: "scim/get-provisioning-information-for-user" do
    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization)
    deliver_error!(error_code, message: error_msg) if error_code

    control_access :org_scim_reader,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true


    @external_identity = organization.saml_provider.external_identities.
      find_by_guid(params[:external_identity_guid])
    deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity
    deliver_scim(:scim_identity_hash, @external_identity)
  end

  # provision an external identity
  post "/scim/v2/organizations/:organization_id/Users", operation_id: "scim/provision-and-invite-user" do
    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization, disable_org_scim: GitHub.flipper[:disable_org_scim].enabled?)
    deliver_error!(error_code, message: error_msg) if error_code

    control_access :manage_org_users,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    json = receive_with_schema("scim-user", "provision")

    user_data = Platform::Provisioning::ScimUserData.load(json)

    if user_data.nil?
      deliver_scim_error! 400,
        scim_type: "invalidSyntax",
        detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.",
        result: nil
    end

    mapper = Platform::Provisioning::MapperWrapper.new(can_migrate_identity: false)

    options = {
      organization_id: organization.id,
      user_data: user_data,
      inviter_id: current_user.id,
      mapper: mapper,
    }

    # If the request is being performed by an app
    # we need to pass along the `IntegrationInstallation`
    # record as the inviter instead of the `Bot`.
    if current_user.can_have_granular_permissions?
      options[:inviter_id]   = current_user.installation.id
      options[:inviter_type] = IntegrationInstallation
    end

    result = Platform::Provisioning::OrganizationIdentityProvisioner.provision_and_invite(**options)

    if result.success?
      deliver_scim(:scim_identity_hash, result.external_identity, status: 201)
    elsif result.invalid_identity_error?
      deliver_scim_error!(result.error_code, scim_type: "uniqueness", result: nil)
    else
      GitHub.logger.error({
        "exception.type" => result.errors.first.reason,
        "exception.message" => result.error_messages,
        "gh.org.id" => organization.id
      })
      deliver_scim_error!(result.error_code, detail: result.errors.full_messages.join(" "), result: result)
    end
  end

  put "/scim/v2/organizations/:organization_id/Users/:external_identity_guid", operation_id: "scim/set-information-for-provisioned-user" do
    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization)
    deliver_error!(error_code, message: error_msg) if error_code

    control_access :manage_org_users,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true
    @external_identity = organization.saml_provider.external_identities.
      find_by_guid(params[:external_identity_guid])
    deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

    json = receive_with_schema("scim-user", "update")
    user_data = Platform::Provisioning::ScimUserData.load(json)

    if user_data.nil?
      deliver_scim_error! 400,
        scim_type: "invalidSyntax",
        detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.",
        result: nil
    end

    result = if json["active"] == false
      Platform::Provisioning::OrganizationIdentityProvisioner.deprovision \
        organization_id: organization.id,
        identity_guid: params[:external_identity_guid],
        actor_id: current_user.id
    else
      Platform::Provisioning::OrganizationIdentityProvisioner.provision \
        organization_id: organization.id,
        identity_guid: params[:external_identity_guid],
        user_data: user_data,
        mapper: Platform::Provisioning::ScimMapper,
        inviter_id: current_user.id
    end

    if result.success?
      deliver_scim(:scim_identity_hash, result.external_identity)
    elsif result.identity_not_found_error?
      deliver_resource_not_found!(params[:external_identity_guid])
    else
      # Something went wrong. Scim doesn't specify how to handle general errors
      # so let's just return an error code from result.
      deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
    end
  end

  # update a user attribute
  patch "/scim/v2/organizations/:organization_id/Users/:external_identity_guid", operation_id: "scim/update-attribute-for-user" do
    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization)
    deliver_error!(error_code, message: error_msg) if error_code

    control_access :manage_org_users,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    @external_identity = organization.saml_provider.external_identities.
      find_by_guid(params[:external_identity_guid])
    deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

    patched_user_data = @external_identity.scim_user_data

    json = receive_with_schema("scim-user", "patch")
    json["Operations"].each do |op|
      if op["op"] == "remove" && op["path"].blank?
        deliver_scim_error!(400, scimType: "noTarget", result: nil)
      elsif op["op"] == "replace" && op["value"].is_a?(Hash) && op["value"]["active"] == false
        # Deprovisioning request
        result = Platform::Provisioning::OrganizationIdentityProvisioner.deprovision \
          organization_id: organization.id,
          identity_guid: params[:external_identity_guid],
          actor_id: current_user.id

        if result.success?
          halt deliver_scim(:scim_identity_hash, result.external_identity)
        else
          deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
        end
      else
        patched_user_data = SCIM::Operation.apply(patched_user_data, op)
      end
    end

    result = Platform::Provisioning::OrganizationIdentityProvisioner.provision \
      organization_id: organization.id,
      identity_guid: params[:external_identity_guid],
      user_data: patched_user_data,
      mapper: Platform::Provisioning::ScimMapper

    if result.success?
      deliver_scim(:scim_identity_hash, result.external_identity)
    else
      # Something went wrong. Scim doesn't specify how to handle general errors
      # so let's just return an error code from result.
      deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
    end
  end

  # deprovision a user from the org
  delete "/scim/v2/organizations/:organization_id/Users/:external_identity_guid", operation_id: "scim/delete-user-from-org" do
    # Introducing strict validation of the scim-user.deprovision
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("scim-user", "deprovision", skip_validation: true)

    organization = find_org!
    error_code, error_msg = scim_processing_error_code?(target: organization)
    deliver_error!(error_code, message: error_msg) if error_code


    control_access :manage_org_users,
      resource: organization,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    @external_identity = organization.saml_provider.external_identities.
      find_by_guid(params[:external_identity_guid])
    deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

    result = Platform::Provisioning::OrganizationIdentityProvisioner.deprovision \
      organization_id: organization.id,
      identity_guid: params[:external_identity_guid],
      actor_id: current_user.id

    if result.success?
      deliver_empty status: 204
    else
      deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
    end
  end
end
