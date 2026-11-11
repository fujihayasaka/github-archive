# typed: true
# frozen_string_literal: true

class Api::EnterpriseActionsOIDCCustomIssuerApi < Api::Enterprise::App
  # Set Actions OIDC Issuer Customisation selection for enterprise
  put "/enterprises/:enterprise_id/actions/oidc/customization/issuer", operation_id: "actions/set-actions-oidc-custom-issuer-policy-for-enterprise" do
    current_enterprise = find_enterprise!

    control_access :write_enterprise_actions_oidc_custom_issuer,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "Must have admin rights to Enterprise."

    data = receive_with_openapi

    EnterpriseOIDCIssuerUrlCustomisation.update_issuer_policy(current_enterprise.id,  data["include_enterprise_slug"])
    deliver_empty status: 204

  end
end
