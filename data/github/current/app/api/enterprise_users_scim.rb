# typed: false
# frozen_string_literal: true

class Api::EnterpriseUsersScim < Api::SCIM::UserSCIM
  include Api::App::SCIMHelpers

  allow_media SCIM::CONTENT_TYPE

  attr_reader :provisioner

  # Bypass IP allow list enforcement for calls to these endpoints since we do
  # not require an allow list to include the IP addresses of an IdP.
  def ip_allowlist_enforceable
    :no
  end

  # GET a list of users
  get "/scim/v2/enterprises/:enterprise_id/Users", operation_id: "enterprise-admin/list-provisioned-identities-enterprise" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      get_users(
        target: enterprise,
      )
    else
      identities = filter_identities(enterprise)

      results = paginated_results(identities)

      deliver_scim(:enterprise_scim_identities_hash, results)
    end
  end

  def filter_identities(enterprise)
    identities = enterprise.external_provider.external_identities.not_deleted.provisioned_by(:scim).unlinked_or_users.with_scim_preloads

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
  get "/scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid", operation_id: "enterprise-admin/get-provisioning-information-for-enterprise-user" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      get_user(
        target: enterprise,
      )
    else
      @external_identity = enterprise.external_provider.external_identities.not_deleted.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity
      deliver_scim(:enterprise_scim_identity_hash, @external_identity)
    end
  end

  # provision an external identity
  post "/scim/v2/enterprises/:enterprise_id/Users", operation_id: "enterprise-admin/provision-enterprise-user" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise, message: "This Enterprise account does not support membership provisioning.")
    block_unsupported_scim_user_agents(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      provision_user(
        target: enterprise,
      )
    else
      json = receive_with_schema("enterprise-scim-user", "provision")

      user_data = Platform::Provisioning::ScimUserData.load(json)
      if user_data.nil?
        deliver_scim_error! 400,
          scim_type: "invalidSyntax",
          detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.",
          result: nil
      end

      if user_data.email.nil?
        deliver_scim_error! 400,
          scim_type: "invalidSyntax",
          detail: "\"emails\" wasn't supplied. If no \"emails\" field is supplied, the \"userName\" field must be a valid email.",
          result: nil
      end

      can_invite = operation_can_invite_identity?(action: :post, user_data: user_data)
      options = {
        target: enterprise,
        user_data: user_data,
        mapper: scim_mapper(can_migrate_identity: true, received_full_groups_info: can_invite),
      }
      result = if can_invite
        apply_identity_invite_operation(options)
      else
        provisioner.provision(**options)
      end

      if result.success?
        deliver_scim(:enterprise_scim_identity_hash, result.external_identity, status: 201)
      elsif result.invalid_identity_error?
        # https://tools.ietf.org/html/rfc7644#section-3.3
        # If the service provider determines that the creation of the requested
        # resource conflicts with existing resources (e.g., a "User" resource
        # with a duplicate "userName"), the service provider MUST return HTTP
        # status code 409 (Conflict) with a "scimType" error code of
        # "uniqueness"
        deliver_scim_error!(result.error_code, scim_type: "uniqueness", result: result)
      else
        # Something unexpected happened. SCIM doesn't define a general error so
        # we'll just respond with an error code from result.
        GitHub.logger.error({
          "exception.type" => result.errors.first.reason,
          "exception.message" => result.error_messages,
          "gh.business.id" => enterprise.id
        })
        deliver_scim_error!(result.error_code, detail: result.errors.full_messages.join(" "), result: result)
      end
    end
  end

  # replace a user attribute
  put "/scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid", operation_id: "enterprise-admin/set-information-for-provisioned-enterprise-user" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      update_user(
        target: enterprise,
      )
    else
      @external_identity = enterprise.saml_provider.external_identities.
          find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

      json = receive_with_schema("enterprise-scim-user", "update")
      user_data = Platform::Provisioning::ScimUserData.load(json)

      if user_data.nil?
        deliver_scim_error! 400,
          scim_type: "invalidSyntax",
          detail: "Either \"emails\", \"roles\", or \"groups\" field was supplied in the incorrect format.  Hash is expected with a \"value\" field.",
          result: nil
      end

      result = if @external_identity.scim_user_data.active? && json["active"] == false
        provisioner.deprovision \
          target: enterprise,
          user_data: user_data,
          identity_guid: params[:external_identity_guid],
          actor_id: current_user.id,
          hard_delete: false
      else
        if user_data.email.nil?
          deliver_scim_error! 400,
            scim_type: "invalidSyntax",
            detail: "\"emails\" wasn't supplied. If no \"emails\" field is supplied, the \"userName\" field must be a valid email.",
            result: nil
        end

        can_invite = operation_can_invite_identity?(action: :put, user_data: user_data)
        options = {
          target: enterprise,
          user_data: user_data,
          mapper: scim_mapper(received_full_groups_info: can_invite),
        }

        if can_invite
          options[:identity] = @external_identity

          apply_identity_invite_operation(options)
        else
          options[:identity_guid] = params[:external_identity_guid]

          provisioner.provision(**options)
        end
      end

      if result.success?
        deliver_scim(:enterprise_scim_identity_hash, result.external_identity)
      else
        # Something went wrong. Scim doesn't specify how to handle general errors
        # so let's just return an error code from result.
        deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
      end
    end
  end

  # update a user attribute
  patch "/scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid", operation_id: "enterprise-admin/update-attribute-for-enterprise-user" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      patch_user(
        target: enterprise,
      )
    else
      @external_identity = enterprise.saml_provider.external_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

      patched_user_data = @external_identity.scim_user_data

      json = receive_with_schema("enterprise-scim-user", "patch")

      process_result = SCIM::Operation.process_json(patched_user_data, json)

      unless process_result.success?
        deliver_scim_error!(process_result.error.status, scim_type: process_result.error.scim_type, result: result)
      end

      patched_user_data = process_result.user_data

      options = {
        target: enterprise,
        user_data: patched_user_data,
      }
      result = if operation_deactivates_identity?(@external_identity.scim_user_data, patched_user_data)
        # Deprovisioning request
        options[:identity_guid] = params[:external_identity_guid]
        options[:actor_id] = current_user.id
        options[:hard_delete] = false

        provisioner.deprovision(**options)
      else
        can_invite = operation_can_invite_identity?(action: :patch,
                                                    user_data: @external_identity.scim_user_data,
                                                    patched_user_data: patched_user_data)
        options[:mapper] = scim_mapper(received_full_groups_info: can_invite)

        if can_invite
          options[:identity] = @external_identity

          apply_identity_invite_operation(options)
        else
          options[:identity_guid] = params[:external_identity_guid]
          options[:identity] = @external_identity

          provisioner.provision(**options)
        end
      end

      if result.success?
        deliver_scim(:enterprise_scim_identity_hash, result.external_identity)
      else
        # Something went wrong. Scim doesn't specify how to handle general errors
        # so let's just return an error code from result.
        deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
      end
    end
  end

  # deprovision a user from the org
  delete "/scim/v2/enterprises/:enterprise_id/Users/:external_identity_guid", operation_id: "enterprise-admin/delete-user-from-enterprise" do
    enterprise = find_enterprise!
    enterprise_scim_enabled(enterprise)
    block_unsupported_scim_user_agents(enterprise)

    control_access :enterprise_scim_writer,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    set_provisioner(enterprise)

    if external_users_enabled?(enterprise)
      delete_user(
        target: enterprise,
      )
    else
      # Introducing strict validation of the scim-user.deprovision
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      receive_with_schema("scim-user", "deprovision", skip_validation: true)

      @external_identity = enterprise.saml_provider.external_identities.
        find_by_guid(params[:external_identity_guid])
      deliver_resource_not_found!(params[:external_identity_guid]) unless @external_identity

      user_data = @external_identity.scim_user_data
      user_data.replace("active", "False")

      result = provisioner.deprovision \
        target: enterprise,
        user_data: user_data,
        identity_guid: params[:external_identity_guid],
        actor_id: current_user.id,
        hard_delete: true

      if result.success?
        deliver_empty status: 204
      else
        deliver_scim_error!(result.error_code, detail: result.error_messages.join("\n"), result: result)
      end
    end
  end

  private

  # Private: Check weather the environment called is enabled for external users SCIM
  #
  # enterprise          - Enterprise where SAML is enabled
  #
  # Returns Boolean
  def external_users_enabled?(enterprise)
    return true if enterprise.enterprise_server_scim_enabled?
    enterprise.enterprise_managed_user_enabled?
  end

  def set_provisioner(target)
    @provisioner = if target.enterprise_server_scim_enabled?
      Platform::Provisioning::EnterpriseServerSCIMIdentityProvisioner
    elsif target.is_a?(Business) && target.enterprise_managed_user_enabled?
      Platform::Provisioning::EnterpriseManagedIdentityProvisioner
    else
      Platform::Provisioning::IdentityProvisioner
    end
  end

  def scim_mapper(can_migrate_identity: false, received_full_groups_info: false)
    Platform::Provisioning::MapperWrapper.new(can_migrate_identity: can_migrate_identity,
                                              received_full_groups_info: received_full_groups_info)
  end

  # Private: Determine whether or not the current operation can invite the identity to the
  # Enterprise. Call #provision_and_invite if invites are possible, and #provision otherwise.
  #
  # For  GHES, the behavior is set: a POST creates and invites the identity. PUT and PATCH
  # only update an identity, but do not invite.
  #
  # For GHEC, behavior is dependent on whether the [optional] `groups` attribute is present. If it
  # is, call #provision_and_invite to sync up the user's org/group memberships. If it isn't, call
  # #provision and don't touch org/group memberships.
  #
  # action              -   HTTP action we're responding to (:post, :put, or :patch)
  # user_data           -   user_data for this user
  # patched_user_data   -   user_data with the PATCH changes applied (only used for :patch case)
  #
  # Returns: Boolean
  def operation_can_invite_identity?(action:, user_data:, patched_user_data: nil)
    case action
    when :post
      user_data.fetch("groups").present?
    when :put
      user_data.fetch("groups").present?
    when :patch
      (user_data.fetch("groups") || patched_user_data.fetch("groups")).present?
    else
      false
    end
  end

  def operation_deactivates_identity?(original_scim_data, patched_scim_data)
    original_scim_data.active? && !patched_scim_data.active?
  end

  def apply_identity_invite_operation(options)
    # If the request is being performed by an app
    # we need to pass along the `IntegrationInstallation`
    # record as the inviter instead of the `Bot`.
    if current_user.bot?
      options[:inviter_id]   = current_user.installation.id
      options[:inviter_type] = IntegrationInstallation
    else
      options[:inviter_id] = current_user.id
    end

    provisioner.provision_and_invite(**options)
  end

end
