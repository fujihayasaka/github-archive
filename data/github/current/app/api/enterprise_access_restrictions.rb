# typed: true
# frozen_string_literal: true

class Api::EnterpriseAccessRestrictions < Api::App
  include ReceiveSchemaWithOpenApi

  # Enable enterprise access restriction
  post "/enterprises/:enterprise_id/access-restrictions/enable", operation_id: "enterprise-admin/enable-access-restrictions", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("enterprise_access_verification_ga", enterprise, default: false)
    deliver_error!(400, message: Configurable::ProxySecurityHeader::UNSUPPORTED_ENTERPRISE_ERROR) unless enterprise.eligible_for_proxy_security_header?

    control_access :enterprise_access_restrictions,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Configurable::ProxySecurityHeader::CORRECT_ACTOR_REQUIRED_ERROR

    unless enterprise.proxy_security_header_enabled?
      with_write do
        enterprise.enable_proxy_security_header(actor: current_user)
      end
    end

    deliver_raw({ message: "Enterprise access restrictions successfully enabled.",
      header_name: "sec-GitHub-allowed-enterprise",
      header_value: enterprise.id.to_s }, status: 200)
  end

  # Disable enterprise access restriction
  post "/enterprises/:enterprise_id/access-restrictions/disable", operation_id: "enterprise-admin/disable-access-restrictions", read_from_replicas: true do
    enterprise = find_enterprise!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?("enterprise_access_verification_ga", enterprise, default: false)
    deliver_error!(400, message: Configurable::ProxySecurityHeader::UNSUPPORTED_ENTERPRISE_ERROR) unless enterprise.eligible_for_proxy_security_header?

    control_access :enterprise_access_restrictions,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Configurable::ProxySecurityHeader::CORRECT_ACTOR_REQUIRED_ERROR

    if enterprise.proxy_security_header_enabled?
      with_write do
        enterprise.disable_proxy_security_header(actor: current_user)
      end
    end

    deliver_raw({ message: "Enterprise access restrictions successfully disabled.",
      header_name: "sec-GitHub-allowed-enterprise",
      header_value: enterprise.id.to_s }, status: 200)
  end
end
