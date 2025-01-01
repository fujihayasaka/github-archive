# typed: true
# frozen_string_literal: true

class Api::RepositoryActionsPermissions < Api::App
  include ReceiveSchemaWithOpenApi

  # These are used for both setting the top-level policy for enabling or
  # disabling Actions AND specifying allowable action and workflow types.
  ALL = Configurable::ActionsAccess::ALL_ENTITIES
  SELECTED = Configurable::ActionsAccess::SELECTED_ENTITIES

  # For disabling Actions only.
  NONE = Configurable::ActionsAccess::NO_ENTITIES

  # For specifying allowable types only.
  LOCAL_ONLY = Actions::AllowedTypesUpdater::LOCAL_ONLY

  # For external workflow access
  NOT_ACCESSIBLE = "none"
  ACCESSIBLE_SAME_ORGANIZATION = "organization"
  ACCESSIBLE_SAME_BUSINESS = "enterprise"
  ACCESSIBLE_SAME_USER = "user"

  # Get the repo permission for running actions and workflows
  get "/repositories/:repository_id/actions/permissions", operation_id: "actions/get-github-actions-permissions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :read_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_READ_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :read_admin_actions,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    enabled = !current_repo.actions_disabled?

    if enabled
      if current_repo.allows_all_actions?
        allowed_actions = ALL
      elsif current_repo.allows_specified_actions?
        allowed_actions = SELECTED
        selected_actions_url = url("/repositories/#{current_repo.id}/actions/permissions/selected-actions")
      else
        allowed_actions = LOCAL_ONLY
      end
    end

    deliver :actions_repository_permissions_hash,  {
      enabled: enabled,
      allowed_actions: allowed_actions,
      selected_actions_url: selected_actions_url
    }
  end

  # Set the repo permission for running actions and workflows
  put "/repositories/:repository_id/actions/permissions", operation_id: "actions/set-github-actions-permissions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :write_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_WRITE_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :write_admin_actions_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    data = receive_with_schema("repository-actions-permission", "set-permission", expected_type: Hash)
    enabled = data["enabled"]
    allowed_actions = data["allowed_actions"]

    # First, check that new permissions are compatible with owner's permissions
    if !enabled
      deliver_error! 409, errors: "You can't specify 'allowed_actions' unless enabled is true." unless allowed_actions.nil?
    else
      # Check compatibility of enabling Actions with owner's permissions
      check_actions_allowed_by_owner!

      # Check compatibility of allowed actions with owner's permissions
      case owner_actions_permissions
      when LOCAL_ONLY
        deliver_error! 409, errors: "Only 'local_only' #{policy_text} are allowed in this organization." unless allowed_actions == LOCAL_ONLY
      when SELECTED
        deliver_error! 409, errors: "Only 'selected' or 'local_only' #{policy_text} are allowed in this organization." if allowed_actions == ALL
      end
    end

    # The top-level policy can only ever be fully enabled or fully disabled.
    # Repos do not have sub-entities like orgs and enterprises do, so we have to
    # normalize this value here.
    access_policy = enabled ? Configurable::ActionsAccess::ALL_ENTITIES : Configurable::ActionsAccess::NO_ENTITIES

    Actions::PolicyUpdater.perform(
      entity: current_repo,
      policy: access_policy,
      actor: current_user
    )

    if !current_repo.reload.actions_disabled? && allowed_actions.present?
      Actions::AllowedTypesUpdater.perform(
        entity: current_repo,
        policy: allowed_actions,
        actor: current_user
      )
    end

    deliver_empty status: 204
  end

  # Get selected actions and workflows for this repository
  get "/repositories/:repository_id/actions/permissions/selected-actions", operation_id: "actions/get-allowed-actions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :read_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_READ_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :read_admin_actions,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    check_allow_specified_actions!

    github_owned_allowed = current_repo.allows_github_owned_actions?
    verified_allowed = current_repo.allows_verified_actions?
    patterns_allowed = resolved_allowlist_patterns

    deliver :actions_repository_selected_actions_hash, {
      github_owned_allowed: github_owned_allowed,
      verified_allowed: verified_allowed,
      patterns_allowed: patterns_allowed
    }
  end

  # Set selected actions and workflows for this repository
  put "/repositories/:repository_id/actions/permissions/selected-actions", operation_id: "actions/set-allowed-actions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :write_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_WRITE_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :write_admin_actions_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    data = receive_with_schema("repository-actions-selected", "update-selected", expected_type: Hash)
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

    check_allow_specified_actions!
    check_can_update_specified_actions!
    check_can_update_patterns! if patterns_allowed.present?

    # Allow passing in nil values to keep existing value. Note that [] means clearing up the list of patterns.
    github_owned_allowed = current_repo.allows_github_owned_actions? if github_owned_allowed.nil?
    verified_allowed = current_repo.allows_verified_actions? if verified_allowed.nil?

    if !github_owned_allowed && !verified_allowed && !patterns_allowed.present?
      if GitHub.multi_tenant_enterprise?
        deliver_error! 409, errors: "You cannot have 'github_owned_allowed' and 'patterns_allowed' both disabled at the same time. If you want to allow local #{policy_text} only, set 'local_only' for 'allowed_actions' on #{url("/repositories/#{current_repo.id}/actions/permissions")}."
      else
        deliver_error! 409, errors: "You cannot have 'verified_allowed', 'github_owned_allowed', and 'patterns_allowed' all disabled at the same time. If you want to allow local #{policy_text} only, set 'local_only' for 'allowed_actions' on #{url("/repositories/#{current_repo.id}/actions/permissions")}."
      end
    end

    maximum_patterns = ActionsPolicy::Allowlist::MAXIMUM_PATTERNS
    if (patterns_allowed || []).length > maximum_patterns
      deliver_error! 409, errors: "You can only add up to #{maximum_patterns} patterns in 'patterns_allowed'."
    end
    # Now we can proceed
    unless patterns_allowed.nil?
      allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(current_repo, patterns: patterns_allowed, actor: current_user)
      deliver_error! 409, errors: allowlist.errors.first&.message if allowlist.errors.present?
    end

    current_repo.enable_specified_actions_only(github_owned: github_owned_allowed, verified: verified_allowed, actor: current_user)

    deliver_empty status: 204
  end

  # Get the workflow access to this repository
  get "/repositories/:repository_id/actions/permissions/access", operation_id: "actions/get-workflow-access-to-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :read_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_READ_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :read_admin_actions,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    deliver_error! 422, message: "Access policy only applies to internal and private repositories." unless current_repo.is_actions_repository_sharing_applicable?

    policy = current_repo.actions_repository_share_policy

    access_level =
      case policy
      when Configurable::ActionsRepositorySharePolicy::NONE
        NOT_ACCESSIBLE
      when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION
        ACCESSIBLE_SAME_ORGANIZATION
      when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS
        ACCESSIBLE_SAME_BUSINESS
      when Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_USER
        ACCESSIBLE_SAME_USER
      end

    deliver :actions_repository_share_policy_hash,  {
      access_level: access_level,
    }
  end

  # Set the workflow access to this repository
  put "/repositories/:repository_id/actions/permissions/access", operation_id: "actions/set-workflow-access-to-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :write_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_WRITE_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :write_admin_actions_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    deliver_error! 422, message: "Access policy only applies to internal and private repositories." unless current_repo.is_actions_repository_sharing_applicable?

    data = receive_with_openapi

    policy =
      case data["access_level"]
      when NOT_ACCESSIBLE
        Configurable::ActionsRepositorySharePolicy::NONE
      when ACCESSIBLE_SAME_ORGANIZATION
        Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_ORGANIZATION
      when ACCESSIBLE_SAME_BUSINESS
        Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_BUSINESS
      when ACCESSIBLE_SAME_USER
        Configurable::ActionsRepositorySharePolicy::ACCESSIBLE_SAME_USER
      end

    if current_repo.owner.business.present?
      deliver_error! 422, errors: "Only 'none', 'organization', and 'enterprise' access levels are allowed for this repository." unless Configurable::ActionsRepositorySharePolicy::ENTERPRISE_ORG_OPTIONS.include?(policy)
    elsif current_repo.owner.organization?
      deliver_error! 422, errors: "Only 'none' and 'organization' access levels are allowed for this repository." unless Configurable::ActionsRepositorySharePolicy::NON_ENTERPRISE_ORG_OPTIONS.include?(policy)
    else
      deliver_error! 422, errors: "Only 'none' and 'user' access levels are allowed for this repository." unless Configurable::ActionsRepositorySharePolicy::OUTSIDE_ORG_OPTIONS.include?(policy)
    end

    if policy != Configurable::ActionsRepositorySharePolicy::NONE && !current_repo.actions_app_installed?
      ActiveRecord::Base.connected_to(role: :writing) do
        result = current_repo.enable_actions_app(
          actor: current_user,
          entry_point: :rest_api_set_workflow_actions_for_repository_enable_actions_app
        )
        if !result.success?
          # nwo used for logging therefore safe to use here.
          GitHub.logger.info(
            "Unable to setup actions app for the repository",
            "gh.repo.name_with_owner" => current_repo.nwo, # rubocop:disable GitHub/DoNotAllowNameWithOwner
            "gh.repo.id" => current_repo.id,
            "gh.repo.enable_actions_app_result_reason" => result.reason
          )
        end
      end
    end

    current_repo.set_actions_repository_share_policy(policy: policy, actor: current_user)

    deliver_empty status: 204
  end

  # Get the default actions workflow permissions for a repository
  get "/repositories/:repository_id/actions/permissions/workflow", operation_id: "actions/get-github-actions-default-workflow-permissions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :read_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_READ_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :read_admin_actions,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    # values: read, write; but write is not saved in the database and returns empty string or nil
    default_workflow_permissions = current_repo.actions_default_workflow_permissions
    if default_workflow_permissions != "read"
      default_workflow_permissions = "write"
    end

    can_approve_pull_request_reviews = current_repo.actions_workflow_permission_can_approve_pr?

    deliver :actions_default_workflow_permissions_hash, {
      default_workflow_permissions: default_workflow_permissions,
      can_approve_pull_request_reviews: can_approve_pull_request_reviews
    }
  end

  # Set the default actions workflow permissions for an repository
  put "/repositories/:repository_id/actions/permissions/workflow", operation_id: "actions/set-github-actions-default-workflow-permissions-repository" do
    deliver_error! 404 unless actions_permissions_enabled?

    if current_repo.owner.feature_enabled?(:repo_ci_cd_admin)
      control_access :write_actions_settings_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        forbid_message: ActionsCiCdErrors::REPO_ACTIONS_POLICIES_WRITE_FORBIDDEN_MESSAGE,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    else
      control_access :write_admin_actions_repo,
        resource: current_repo,
        forbid: current_repo.public?,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true
    end

    data = receive_with_openapi
    default_workflow_permissions = data["default_workflow_permissions"]
    can_approve_pull_request_reviews = data["can_approve_pull_request_reviews"]

    if !current_repo.actions_can_have_default_workflow_permissions_read_write? && default_workflow_permissions == "write"
      source = current_repo.actions_default_workflow_permissions_source.is_a?(Organization) ? "organization" : "enterprise"
      deliver_error! 409, errors: "Write permissions for workflows are disabled by the #{source}"
    end

    if !current_repo.actions_workflow_permission_can_allow_pr_approval? && can_approve_pull_request_reviews
      source = current_repo.actions_workflow_permission_can_approve_pr_source.is_a?(Organization) ? "organization" : "enterprise"
      deliver_error! 409, errors: "The #{source} does not allow GitHub Actions to create or approve pull requests"
    end

    if !default_workflow_permissions.nil?
      current_repo.set_default_workflow_permissions(default_workflow_permissions, current_user)
    end

    if !can_approve_pull_request_reviews.nil?
      current_repo.set_actions_workflow_permission_can_approve_pr(can_approve_pull_request_reviews, current_user)
    end

    # check if saving worked as expected and if not return the error message
    if current_repo.errors.any?
      deliver_error! 409, errors: "Error saving your changes: #{current_repo.errors.full_messages.join(", ")}"
    end

    deliver_empty status: 204
  end

  private

  def actions_permissions_enabled?
    GitHub.actions_enabled?
  end

  def resolved_allowlist_patterns
    current_repo.highest_level_allowlist&.allowed_action_patterns.order(:id).pluck(:value) || []
  end

  def owner_actions_permissions
    return ALL if current_repo.owner.user?

    return LOCAL_ONLY if current_repo.owner_allows_local_actions_only?
    return SELECTED if current_repo.owner_allows_specified_actions_only?
    ALL
  end

  def check_actions_allowed_by_owner!
    return if current_repo.owner.user?

    deliver_error! 409, errors: "GitHub Actions is disabled on this repository by the organization" if current_repo.actions_disabled_by_owner?
    deliver_error! 409, errors: "GitHub Actions is disabled in this organization" if current_repo.owner.actions_disabled?
    return unless current_repo.owner.business.present?

    deliver_error! 409, errors: "GitHub Actions is disabled in this organization by the enterprise" if current_repo.owner.actions_disabled_by_owner?
    deliver_error! 409, errors: "GitHub Actions is disabled in this enterprise" if current_repo.owner.business.actions_disabled?
  end

  def check_allow_specified_actions!
    check_actions_allowed_by_owner!

    deliver_error! 409, errors: "GitHub Actions is disabled on this repository" if current_repo.actions_disabled?
    return if current_repo.allows_specified_actions?

    deliver_error! 409, errors: "All #{policy_text} are allowed on this repository" if current_repo.allows_all_actions?
    deliver_error! 409, errors: "Only local #{policy_text} are allowed on this repository" if current_repo.allows_local_actions_only?
  end

  def check_can_update_specified_actions!
    deliver_error! 409, errors: "Selected #{policy_text} are already set at the organization or enterprise level" if current_repo.owner_restricts_allowed_actions?
  end

  def check_can_update_patterns!
    return if current_repo.can_use_actions_allowlist?

    deliver_error! 409, errors: "Specific patterns can only be set on public repositories or when on an Enterprise plan."
  end

  def policy_text
    "actions and workflows"
  end
end
