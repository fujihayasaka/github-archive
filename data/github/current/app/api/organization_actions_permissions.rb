# typed: false
# frozen_string_literal: true

class Api::OrganizationActionsPermissions < Api::App
  include ReceiveSchemaWithOpenApi
  # These are used for both setting the top-level policy for enabling or
  # disabling Actions AND specifying allowable action and workflow types.
  ALL = Configurable::ActionsAccess::ALL_ENTITIES
  SELECTED = Configurable::ActionsAccess::SELECTED_ENTITIES

  # For disabling Actions only.
  NONE = Configurable::ActionsAccess::NO_ENTITIES

  # For specifying allowable types only.
  LOCAL_ONLY = Actions::AllowedTypesUpdater::LOCAL_ONLY

  # Get the org policy for running actions and workflows
  get "/organizations/:organization_id/actions/permissions", operation_id: "actions/get-github-actions-permissions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :read_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    if current_org.actions_disabled?
      enabled_repositories = NONE
    elsif current_org.actions_enabled_for_selected_entities?
      enabled_repositories = SELECTED
    else
      enabled_repositories = ALL
    end

    if enabled_repositories != NONE
      if current_org.allows_all_actions?
        allowed_actions = ALL
      elsif current_org.allows_specified_actions?
        allowed_actions = SELECTED
        selected_actions_url = url("/organizations/#{current_org.id}/actions/permissions/selected-actions")
      else
        allowed_actions = LOCAL_ONLY
      end
    end

    if enabled_repositories == SELECTED
      selected_repositories_url = url("/organizations/#{current_org.id}/actions/permissions/repositories")
    end

    deliver :actions_organization_permissions_hash, {
      enabled_repositories: enabled_repositories,
      selected_repositories_url: selected_repositories_url,
      allowed_actions: allowed_actions,
      selected_actions_url: selected_actions_url
    }
  end

  # Set the org policy for running actions and workflows
  put "/organizations/:organization_id/actions/permissions", operation_id: "actions/set-github-actions-permissions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("organization-actions-permission", "set-permission", expected_type: Hash)
    enabled_repositories = data["enabled_repositories"]
    allowed_actions = data["allowed_actions"]

    if enabled_repositories == NONE && !allowed_actions.nil?
      deliver_error! 409, errors: "You can't specify 'allowed_actions' unless you enable some repositories."
    else
      deliver_error! 409, errors: "GitHub Actions is disabled on this organization by the enterprise" if current_org.actions_disabled_by_owner?
    end

    policy_text = policy_text(current_org)
    case owner_actions_permissions(current_org)
    when LOCAL_ONLY
      deliver_error! 409, errors: "Only 'local_only' #{policy_text} are allowed in this enterprise." unless allowed_actions == LOCAL_ONLY
    when SELECTED
      deliver_error! 409, errors: "Only 'selected' or 'local_only' #{policy_text} are allowed in this enterprise." if allowed_actions == ALL
    end

    Actions::PolicyUpdater.perform(
      entity: current_org,
      policy: enabled_repositories,
      actor: current_user
    )

    if !current_org.reload.actions_disabled? && allowed_actions.present?
      Actions::AllowedTypesUpdater.perform(
        entity: current_org,
        policy: allowed_actions,
        actor: current_user
      )
    end

    deliver_empty status: 204
  end

  # Get the list of repos enabled for Actions under this organization, paginated.
  get "/organizations/:organization_id/actions/permissions/repositories", operation_id: "actions/list-selected-repositories-enabled-github-actions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :read_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_permissions_selected!(current_org)

    # Repos that have a config entry Configurable::ActionsAllowedByOwner are allowed by this organization.
    # We don't have a direct mapping from this organization to the allowed repos, so scan them all.
    enabled_repos = current_org.repositories.order(:name).where(id: current_org.actions_allowed_entities)
    paginated_repo = paginate_rel(enabled_repos)

    deliver :actions_organization_allowed_repositories_hash,  {
      total_count: enabled_repos.count,
      repositories: paginated_repo
    }
  end

  # Set the list of repos enabled for Actions under this organization.
  put "/organizations/:organization_id/actions/permissions/repositories", operation_id: "actions/set-selected-repositories-enabled-github-actions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true


    check_permissions_selected!(current_org)

    data = receive_with_schema("organization-actions-permission-repository", "update-repositories", expected_type: Hash)
    selected_repo_ids = data["selected_repository_ids"]

    # Repos that have a config entry Configurable::ActionsAllowedByOwner are allowed by this organization.
    all_repos = current_org.repositories
    all_repo_ids = all_repos.map { |repo| repo.id }

    # Verify that the list matches repos within this organization
    if all_repo_ids.intersection(selected_repo_ids).count != selected_repo_ids.count
      deliver_error! 422, errors: "Some repositories in the given list do not belong to this organization."
    end

    # Update each repo to reflect the new setting
    Actions::AllowActionsInSelectedReposJob.perform_later(current_org, selected_repo_ids, current_user)

    deliver_empty status: 204
  end

  # Add a single repo to the list of allowed repos
  put "/organizations/:organization_id/actions/permissions/repositories/:repository_id", operation_id: "actions/enable-selected-repository-github-actions-organization" do
    current_org = find_org!
    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_permissions_selected!(current_org)
    repository = find_and_check_repo!(current_org)
    repository.allow_actions actor: current_user unless repository.actions_allowed_by_owner?

    deliver_empty status: 204
  end

  # Remove a single repo to the list of allowed repos
  delete "/organizations/:organization_id/actions/permissions/repositories/:repository_id", operation_id: "actions/disable-selected-repository-github-actions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_permissions_selected!(current_org)
    repository = find_and_check_repo!(current_org)
    repository.disallow_actions actor: current_user if repository.actions_allowed_by_owner?

    deliver_empty status: 204
  end

  # Get the selected actions and workflows for an organization
  get "/organizations/:organization_id/actions/permissions/selected-actions", operation_id: "actions/get-allowed-actions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :read_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    check_allow_specified_actions!(current_org)

    github_owned_allowed = current_org.allows_github_owned_actions?
    verified_allowed = current_org.allows_verified_actions?
    patterns_allowed = if current_org.allows_specific_actions_patterns?
      current_org.highest_level_allowlist&.allowed_action_patterns.order(:id).pluck(:value)
    else
      []
    end

    deliver :actions_organization_selected_actions_hash, {
      github_owned_allowed: github_owned_allowed,
      verified_allowed: verified_allowed,
      patterns_allowed: patterns_allowed
    }
  end

  # Set the selected actions and workflows for an organization
  put "/organizations/:organization_id/actions/permissions/selected-actions", operation_id: "actions/set-allowed-actions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_schema("organization-actions-selected", "update-selected", expected_type: Hash)
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

    github_owned_allowed = current_org.allows_github_owned_actions? if github_owned_allowed.nil?
    verified_allowed = current_org.allows_verified_actions? if verified_allowed.nil?

    check_allow_specified_actions!(current_org)
    all_parameters_disabled = !github_owned_allowed && !verified_allowed && !patterns_allowed.present?
    check_can_update_specified_actions!(current_org, all_parameters_disabled)

    current_org.enable_specified_actions_only(github_owned: github_owned_allowed, verified: verified_allowed, actor: current_user)

    maximum_patterns = ActionsPolicy::Allowlist::MAXIMUM_PATTERNS
    if !patterns_allowed.nil? && patterns_allowed.length > maximum_patterns
      deliver_error! 409, errors: "You can only add up to #{maximum_patterns} patterns in 'patterns_allowed'."
    end
    unless patterns_allowed.nil?
      allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(current_org, patterns: patterns_allowed, actor: current_user)
      deliver_error! 409, errors: allowlist.errors.first&.message if allowlist.errors.present?
    end

    deliver_empty status: 204
  end

  # Get the default actions workflow permissions for an organization
  get "/organizations/:organization_id/actions/permissions/workflow", operation_id: "actions/get-github-actions-default-workflow-permissions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :read_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # values: read, write; but write is not saved in the database and returns empty string or nil
    default_workflow_permissions = current_org.actions_default_workflow_permissions
    if default_workflow_permissions != "read"
      default_workflow_permissions = "write"
    end
    # values: true, false; but true is not saved in the database only false
    can_approve_pull_request_reviews = current_org.actions_workflow_permission_can_approve_pr?

    deliver :actions_default_workflow_permissions_hash, {
      default_workflow_permissions: default_workflow_permissions,
      can_approve_pull_request_reviews: can_approve_pull_request_reviews
    }
  end

  # Set the default actions workflow permissions for an organization
  put "/organizations/:organization_id/actions/permissions/workflow", operation_id: "actions/set-github-actions-default-workflow-permissions-organization" do
    current_org = find_org!

    deliver_error! 404 unless actions_permissions_enabled?(current_org)

    control_access :write_actions_settings_org,
      resource: current_org,
      forbid: true,
      forbid_message: Api::App::ActionsCiCdErrors::ORG_ACTIONS_POLICIES_FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    # does it's magic and all should be set like defined in OpenAPI spec (operation_id)
    # in our case no additional input validation is needed
    data = receive_with_openapi
    default_workflow_permissions = data["default_workflow_permissions"]
    can_approve_pull_request_reviews = data["can_approve_pull_request_reviews"]

    if !current_org.actions_can_have_default_workflow_permissions_read_write? && default_workflow_permissions == "write"
      deliver_error! 409, errors: "Write permissions for workflows are disabled by the enterprise"
    end

    if !current_org.actions_workflow_permission_can_allow_pr_approval? && can_approve_pull_request_reviews
      deliver_error! 409, errors: "The enterprise does not allow GitHub Actions to approve pull requests"
    end

    unless default_workflow_permissions.nil?
      current_org.set_default_workflow_permissions(default_workflow_permissions, current_user)
    end

    unless can_approve_pull_request_reviews.nil?
      current_org.set_actions_workflow_permission_can_approve_pr(can_approve_pull_request_reviews, current_user)
    end

    # check if saving worked as expected and if not return the error message
    if current_org.errors.any?
      deliver_error! 409, errors: "Error saving your changes: #{current_org.errors.full_messages.join(", ")}"
    end

    deliver_empty status: 204
  end

  private

  def owner_actions_permissions(current_org)
    return LOCAL_ONLY if current_org.owner_allows_local_actions_only?
    return SELECTED if current_org.owner_allows_specified_actions_only?
    ALL
  end

  def find_and_check_repo!(current_org)
    repo = Repository.find_by_id(params[:repository_id].to_i)

    deliver_error! 404 unless repo
    deliver_error! 422 unless repo.owner_id == current_org.id

    repo
  end

  # Safety check for PUT/GET list and PUT/DELETE individual orgs
  def check_permissions_selected!(current_org)
    case current_org.actions_access
    when SELECTED
    when NONE
      deliver_error! 409, errors: "GitHub Actions is disabled for all repositories"
    when ALL
      deliver_error! 409, errors: "GitHub Actions is enabled for all repositories"
    else
      deliver_error! 409, errors: "Actions state in this organization is invalid. Please first set the permissions by calling the permissions API at: #{url("/organizations/#{current_org.id}/actions/permissions")}"
    end
  end

  def check_allow_specified_actions!(current_org)
    deliver_error! 409, errors: "GitHub Actions is disabled on this organization" if current_org.actions_disabled?
    deliver_error! 409, errors: "GitHub Actions is disabled on this organization by the enterprise" if current_org.actions_disabled_by_owner?
    return if current_org.allows_specified_actions?
    policy_text = policy_text(current_org)
    deliver_error! 409, errors: "All #{policy_text} are allowed on this organization" if current_org.allows_all_actions?
    deliver_error! 409, errors: "Only local #{policy_text} are allowed on this organization" if current_org.allows_local_actions_only?
  end

  def check_can_update_specified_actions!(current_org, all_parameters_disabled)
    policy_text = policy_text(current_org)
    deliver_error! 409, errors: "Selected #{policy_text} are already set at the enterprise level" if current_org.owner_restricts_allowed_actions?
    if all_parameters_disabled
      if GitHub.multi_tenant_enterprise?
        deliver_error! 409, errors: "You cannot have 'github_owned_allowed' and 'patterns_allowed' both disabled at the same time. If you want to allow local #{policy_text} only, set 'local_only' for 'allowed_actions' on #{url("/enterprises/#{current_org.id}/actions/permissions")}."
      else
        deliver_error! 409, errors: "You cannot have 'verified_allowed', 'github_owned_allowed', and 'patterns_allowed' all disabled at the same time. If you want to allow local #{policy_text} only, set 'local_only' for 'allowed_actions' on #{url("/enterprises/#{current_org.id}/actions/permissions")}."
      end
    end
  end

  def actions_permissions_enabled?(current_org)
    GitHub.actions_enabled?
  end

  def policy_text(current_org)
    "actions and workflows"
  end
end
