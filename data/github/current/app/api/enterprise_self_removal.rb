# typed: true
# frozen_string_literal: true

class Api::EnterpriseSelfRemoval < Api::Enterprise::App
  # Self-removal endpoint is excluded from Conditional Access Policy (CAP) enforcement
  # because it doesn't access protected organization resources. Users removing themselves
  # from an enterprise only affects their own membership status, not organization data.
  # This follows the same security model as the controller implementation.
  # See: Enterprises::MembershipsController#ACTIONS_EXCLUDED_FROM_CAP_CHECKS
  ACTIONS_EXCLUDED_FROM_CAP_CHECKS = ["destroy"]

  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_CHECKS.include?(action_name)
    super
  end

  private

  # Map HTTP method to Rails action name for CAP exclusion checks
  def action_name
    case request.request_method.downcase
    when "delete"
      "destroy"
    else
      "unknown"
    end
  end

  # DELETE /enterprises/:enterprise_id/memberships/:username
  delete "/enterprises/:enterprise_id/memberships/:username", operation_id: "enterprise-admin/remove-membership-for-user", read_from_replicas: true do
    enterprise = find_enterprise!

    # Most permissive access control - just require authentication
    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Only allow users to remove themselves
    unless params[:username] == current_user.display_login
      deliver_error!(403, message: "You can only remove yourself from an enterprise.")
    end

    # Must be an exclusive unaffiliated member (no organization memberships)
    unless enterprise.exclusive_unaffiliated_member?(current_user)
      deliver_error!(403, message: "Only unaffiliated users can remove themselves from the enterprise.")
    end

    begin
      # For self-removal, use force: true to bypass admin permission checks
      # since users should always be able to remove themselves
      enterprise.remove_member(current_user, actor: current_user, force: true, reason: "self_removed")
      status 204
    rescue Business::InvalidRemovalError => e
      deliver_error!(422, message: e.message)
    end
  end
end
