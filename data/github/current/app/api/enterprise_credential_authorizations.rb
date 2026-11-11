# typed: true
# frozen_string_literal: true

class Api::EnterpriseCredentialAuthorizations < Api::Enterprise::App
  include ReceiveSchemaWithOpenApi

  # POST /enterprises/{enterprise}/credential-authorizations/revoke-all
  # Revokes all credential authorizations for all organizations within the enterprise.
  # If the enterprise is an EMU enterprise and the `revoke_credentials` parameter is true,
  # this will also destroy all credentials (PATs and SSH keys) owned by enterprise members.
  post "/enterprises/:enterprise_id/credential-authorizations/revoke-all", operation_id: "enterprise-admin/revoke-all-credential-authorizations", read_from_replicas: true do
    enterprise = find_enterprise!

    control_access :standard_authorization,
      resource: enterprise,
      permission: :write_enterprise_credentials,
      forbid: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi(required: false)

    revoke_credentials = data["revoke_credentials"] == true

    # Only EMU enterprises can revoke credentials themselves
    if revoke_credentials && !enterprise.enterprise_managed?
      deliver_error! 422, message: "The `revoke_credentials` option is only available for Enterprise Managed User (EMU) enterprises"
    end

    # Queue the background job to perform the revocation
    RevokeEnterpriseCredentialAuthorizationsJob.perform_later(
      current_user.id,
      enterprise.id,
      revoke_emu_credentials: revoke_credentials
    )

    response_body = {
      message: "Credential authorization revocation has been queued"
    }

    # If the current request is authenticated with a PAT, warn that it may be revoked/destroyed
    if current_user_authenticated_with_pat?
      if revoke_credentials
        response_body[:warning] = "The token used for this request may also be destroyed as part of this operation"
      else
        response_body[:warning] = "The token used for this request may also have its authorization revoked as part of this operation"
      end
    end

    deliver_raw response_body, status: 202
  end

  private

  # Check if the current user is authenticated with a personal access token
  def current_user_authenticated_with_pat?
    current_user&.using_personal_access_token? || false
  end
end
