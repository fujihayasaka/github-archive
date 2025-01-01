# typed: false
# frozen_string_literal: true

class Api::EnterpriseActionsPermissions < Api::Enterprise::App
  # These are used for both setting the top-level policy for enabling or
  # disabling Actions AND specifying allowable action and workflow types.
  ALL = Configurable::ActionsAccess::ALL_ENTITIES
  SELECTED = Configurable::ActionsAccess::SELECTED_ENTITIES

  # For disabling Actions only.
  NONE = Configurable::ActionsAccess::NO_ENTITIES

  # For specifying allowable types only.
  LOCAL_ONLY = Actions::AllowedTypesUpdater::LOCAL_ONLY

  # Get the enterprise permission for actions and workflows
  get "/enterprises/:enterprise_id/actions/permissions", operation_id: "enterprise-admin/get-github-actions-permissions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :read_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    enabled_organizations = current_enterprise.actions_access || ALL

    if enabled_organizations == SELECTED
      selected_organizations_url = url("/enterprises/#{current_enterprise.id}/actions/permissions/organizations")
    end

    if enabled_organizations != NONE
      if current_enterprise.allows_all_actions?
        allowed_actions = ALL
      elsif current_enterprise.allows_specified_actions?
        allowed_actions = SELECTED
        selected_actions_url = url("/enterprises/#{current_enterprise.id}/actions/permissions/selected-actions")
      else
        allowed_actions = LOCAL_ONLY
      end
    end

    deliver :actions_enterprise_permissions_hash,  {
      enabled_organizations: enabled_organizations,
      selected_organizations_url: selected_organizations_url,
      allowed_actions: allowed_actions,
      selected_actions_url: selected_actions_url
    }
  end

  # Set the enterprise permission for actions and workflows
  put "/enterprises/:enterprise_id/actions/permissions", operation_id: "enterprise-admin/set-github-actions-permissions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    data = receive_with_schema("enterprise-actions-permission", "set-permission", expected_type: Hash)

    enabled_orgs = data["enabled_organizations"]
    allowed_actions = data["allowed_actions"]

    if (enabled_orgs == NONE) && !allowed_actions.nil?
      deliver_error! 409, errors: "You can't specify 'allowed_actions' if no organization is enabled."
    end


    Actions::PolicyUpdater.perform(
      entity: current_enterprise,
      policy: enabled_orgs,
      actor: current_user
    )

    unless current_enterprise.actions_disabled?
      Actions::AllowedTypesUpdater.perform(
        entity: current_enterprise,
        policy: allowed_actions,
        actor: current_user
      )
    end

    deliver_empty status: 204
  end

  # Get the list of orgs enabled for Actions under this enterprise, paginated.
  get "/enterprises/:enterprise_id/actions/permissions/organizations", operation_id: "enterprise-admin/list-selected-organizations-enabled-github-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :read_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    # Orgs that have a config entry Configurable::ActionsAllowedByOwner are allowed by this enterprise.
    # We don't have a direct mapping from this enterprise to the allowed orgs, so scan them all.
    all_orgs = current_enterprise.organizations.order(:login)
    enabled_orgs = all_orgs.select { |org| org.actions_allowed_by_owner? }
    paginated_orgs = paginate_rel(enabled_orgs)

    deliver :actions_enterprise_allowed_organizations_hash, {
      total_count: enabled_orgs.count,
      organizations: paginated_orgs
    }
  end

  # Set the list of orgs enabled for Actions under this enterprise.
  put "/enterprises/:enterprise_id/actions/permissions/organizations", operation_id: "enterprise-admin/set-selected-organizations-enabled-github-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    data = receive_with_schema("enterprise-actions-organization-list", "update-organizations", expected_type: Hash)
    selected_org_ids = data["selected_organization_ids"]

    # Orgs that have a config entry Configurable::ActionsAllowedByOwner are allowed by this enterprise.
    all_orgs = current_enterprise.organizations
    all_org_ids = all_orgs.map { |org| org.id }

    # Verify that the list matches orgs within this enterprise
    if all_org_ids.intersection(selected_org_ids).count != selected_org_ids.count
      deliver_error! 422, errors: "Some organizations in the given list do not belong to this enterprise."
    end

    # Update each org to reflect the new setting
    all_orgs.each do |org|
      if selected_org_ids.include? org.id
        org.allow_actions actor: current_user unless org.actions_allowed_by_owner?
      else
        org.disallow_actions actor: current_user if org.actions_allowed_by_owner?
      end
    end

    deliver_empty status: 204
  end

  # Add a single org to the list of allowed orgs
  put "/enterprises/:enterprise_id/actions/permissions/organizations/:organization_id", operation_id: "enterprise-admin/enable-selected-organization-github-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    organization = find_and_check_org! current_enterprise
    organization.allow_actions actor: current_user unless organization.actions_allowed_by_owner?

    deliver_empty status: 204
  end

  # Remove a single org to the list of allowed orgs
  delete "/enterprises/:enterprise_id/actions/permissions/organizations/:organization_id", operation_id: "enterprise-admin/disable-selected-organization-github-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_permissions_selected! current_enterprise

    organization = find_and_check_org! current_enterprise
    organization.disallow_actions actor: current_user if organization.actions_allowed_by_owner?

    deliver_empty status: 204
  end

  # Get the selected actions and workflows for an enterprise
  get "/enterprises/:enterprise_id/actions/permissions/selected-actions", operation_id: "enterprise-admin/get-allowed-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :read_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_allow_specific_actions! current_enterprise

    github_owned_allowed = current_enterprise.allows_github_owned_actions?
    verified_allowed = current_enterprise.allows_verified_actions?
    patterns_allowed = if current_enterprise.allows_specific_actions_patterns?
      current_enterprise.highest_level_allowlist&.allowed_action_patterns.order(:id).pluck(:value)
    else
      []
    end

    deliver :actions_enterprise_selected_actions_hash, {
      github_owned_allowed: github_owned_allowed,
      verified_allowed: verified_allowed,
      patterns_allowed: patterns_allowed
    }
  end

  # Set the selected actions and workflows for an enterprise
  put "/enterprises/:enterprise_id/actions/permissions/selected-actions", operation_id: "enterprise-admin/set-allowed-actions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
      resource: current_enterprise,
      forbid: false,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: true

    check_allow_specific_actions! current_enterprise

    data = receive_with_schema("enterprise-actions-selected", "update-selected", expected_type: Hash)
    github_owned_allowed = data["github_owned_allowed"]
    verified_allowed = data["verified_allowed"]
    patterns_allowed = data["patterns_allowed"]

    # Setting verified actions is not supported in multi-tenant mode. If that is the only setting provided, return an error.
    if GitHub.multi_tenant_enterprise?
      if !verified_allowed.nil? && patterns_allowed.nil? && github_owned_allowed.nil?
        deliver_error! 422, errors: "Setting 'verified_allowed' is not supported in GHEC with data residency. Other options are still accepted."
      end
      verified_allowed = nil
    end

    # Allow passing in nil values to keep existing value
    github_owned_allowed = current_enterprise.allows_github_owned_actions? if github_owned_allowed.nil?
    verified_allowed = current_enterprise.allows_verified_actions? if verified_allowed.nil?

    if !github_owned_allowed && !verified_allowed && !patterns_allowed.present?
      if GitHub.multi_tenant_enterprise?
        deliver_error! 409, errors: "You cannot have 'github_owned_allowed' and 'patterns_allowed' both disabled at the same time. If you want to allow local #{policy_text(current_enterprise)} only, set 'local_only' for 'allowed_actions' on #{url("/enterprises/#{current_enterprise.id}/actions/permissions")}."
      else
        deliver_error! 409, errors: "You cannot have 'verified_allowed', 'github_owned_allowed', and 'patterns_allowed' all disabled at the same time. If you want to allow local #{policy_text(current_enterprise)} only, set 'local_only' for 'allowed_actions' on #{url("/enterprises/#{current_enterprise.id}/actions/permissions")}."
      end
    end

    current_enterprise.enable_specified_actions_only(
      github_owned: github_owned_allowed,
      verified: verified_allowed,
      actor: current_user,
    )

    maximum_patterns = ActionsPolicy::Allowlist::MAXIMUM_PATTERNS
    if patterns_allowed.present?
      if patterns_allowed.length > maximum_patterns
        deliver_error! 409, errors: "You can only add up to #{maximum_patterns} patterns in 'patterns_allowed'."
      else
        allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(current_enterprise, patterns: patterns_allowed, actor: current_user)
        deliver_error! 409, errors: allowlist.errors.first&.message if allowlist.errors.present?
      end
    end

    deliver_empty status: 204
  end

  # Get the default actions workflow permissions for an organization
  get "/enterprises/:enterprise_id/actions/permissions/workflow", operation_id: "actions/get-github-actions-default-workflow-permissions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :read_actions_admin_enterprise,
                   resource: current_enterprise,
                   forbid: false,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false,
                   enforce_oauth_app_policy: true

    # API values: read, write; but write is not saved in the database and returns empty string or nil
    default_workflow_permissions = current_enterprise.actions_default_workflow_permissions
    default_workflow_permissions = "write" unless default_workflow_permissions == "read"

    can_approve_pull_request_reviews = current_enterprise.actions_workflow_permission_can_approve_pr?

    deliver :actions_default_workflow_permissions_hash, {
      default_workflow_permissions: default_workflow_permissions,
      can_approve_pull_request_reviews: can_approve_pull_request_reviews
    }
  end

  # Set the default actions workflow permissions for an organization
  put "/enterprises/:enterprise_id/actions/permissions/workflow", operation_id: "actions/set-github-actions-default-workflow-permissions-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless actions_permissions_enabled? current_enterprise

    control_access :write_actions_admin_enterprise,
                   resource: current_enterprise,
                   forbid: false,
                   allow_integrations: false,
                   allow_user_via_granular_actor: false,
                   enforce_oauth_app_policy: true

    data = receive_with_openapi

    unless data["default_workflow_permissions"].nil?
      current_enterprise.set_default_workflow_permissions(data["default_workflow_permissions"], current_user)
    end

    unless data["can_approve_pull_request_reviews"].nil?
      current_enterprise.set_actions_workflow_permission_can_approve_pr(data["can_approve_pull_request_reviews"], current_user)
    end

    deliver_empty status: 204
  end

  private

  def actions_permissions_enabled?(current_enterprise)
    return false if current_enterprise.downgraded_to_free_plan?
    GitHub.actions_enabled?
  end

  # Safety check for PUT/GET list and PUT/DELETE individual orgs
  def check_permissions_selected!(current_enterprise)
    return if current_enterprise.actions_access == SELECTED

    deliver_error! 409, errors: "GitHub Actions is disabled for all organizations" if current_enterprise.actions_access == NONE
    deliver_error! 409, errors: "GitHub Actions is enabled for all organizations" if current_enterprise.actions_access == ALL
  end

  def find_and_check_org!(current_enterprise)
    org = Organization.find_by_id(params[:organization_id].to_i)
    deliver_error! 404 unless org
    deliver_error! 422 unless org.business&.id == current_enterprise.id

    org
  end

  def check_allow_specific_actions!(current_enterprise)
    policy_text = policy_text(current_enterprise)
    deliver_error! 409, errors: "GitHub Actions is not allowed on this enterprise" if  current_enterprise.actions_disabled?
    return if current_enterprise.allows_specified_actions?
    deliver_error! 409, errors: "All #{policy_text} are allowed on this enterprise" if current_enterprise.allows_all_actions?
    deliver_error! 409, errors: "Only local #{policy_text} are allowed on this enterprise" if current_enterprise.allows_local_actions_only?
  end

  def policy_text(current_enterprise)
    "actions and workflows"
  end
end
