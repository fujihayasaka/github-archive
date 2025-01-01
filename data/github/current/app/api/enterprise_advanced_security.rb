# typed: true
# frozen_string_literal: true

class Api::EnterpriseAdvancedSecurity < Api::Enterprise::App

  put "/enterprises/:enterprise_id/advanced-security/permissions/organizations/:organization_id", operation_id: :internal do
    current_enterprise = find_enterprise!
    check_enabled!(current_enterprise)

    control_access :write_advanced_security_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    policy = Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL
    params = receive_json(request.body.read)
    if params.present?
      params = params.with_indifferent_access
      deliver_error! 422, errors: "Parameters are not valid." if !params.is_a?(Hash)
      if params[:policy].present?
        policy = params[:policy]
        deliver_error! 422, errors: "Policy is not valid." if !Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_VALUES.include?(policy)
      end
    end

    organization = find_and_check_org! current_enterprise
    organization.set_advanced_security_entity_policy(policy: policy, actor: current_user)

    deliver_empty status: 204
  end

  delete "/enterprises/:enterprise_id/advanced-security/permissions/organizations/:organization_id", operation_id: :internal do
    current_enterprise = find_enterprise!
    check_enabled!(current_enterprise)

    control_access :write_advanced_security_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    organization = find_and_check_org! current_enterprise
    organization.set_advanced_security_entity_policy(policy: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_NONE, actor: current_user)

    deliver_empty status: 204
  end

  sig { params(current_enterprise: Business).void }
  def check_enabled!(current_enterprise)
    deliver_error! 404 unless current_enterprise.advanced_security_purchased?

    return if GitHub.enterprise?

    deliver_error! 404 unless current_enterprise.feature_enabled?(:advanced_security_policy_api)
  end

  def check_permissions_selected!(current_enterprise)
    return if current_enterprise.selected_members_can_enable_advanced_security?

    deliver_error! 409, errors: "GitHub Advanced Security is allowed for all organizations" if current_enterprise.all_members_can_enable_advanced_security?
    deliver_error! 409, errors: "GitHub Advanced Security is not allowed for any organizations" if current_enterprise.no_members_can_enable_advanced_security?
  end

  def find_and_check_org!(current_enterprise)
    org = Organization.find_by(id: params[:organization_id].to_i)
    deliver_error! 404 unless org
    deliver_error! 422 unless org.business&.id == current_enterprise.id

    org
  end

end
