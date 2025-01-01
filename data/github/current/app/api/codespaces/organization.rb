# typed: true
# frozen_string_literal: true

class Api::Codespaces::Organization < Api::Codespaces
  include Api::Codespaces::Helpers::LifecycleHelpers

  SELECTED_MEMBERS = "selected_members"
  ALL_MEMBERS = "all_members"
  ALL_MEMBERS_AND_OUTSIDE_COLLABORATORS = "all_members_and_outside_collaborators"
  DISABLED = "disabled"
  GRANT = "grant"
  REVOKE = "revoke"

  LIMIT_MAPPING = {
    ALL_MEMBERS => Configurable::OrganizationCodespacesUserLimit::ALL_USERS,
    ALL_MEMBERS_AND_OUTSIDE_COLLABORATORS => Configurable::OrganizationCodespacesUserLimit::ALL_USERS_AND_OUTSIDE_COLLABORATORS,
    DISABLED => Configurable::OrganizationCodespacesUserLimit::DISABLED,
    SELECTED_MEMBERS => Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS,
  }

  get "/organizations/:organization_id/codespaces", operation_id: "codespaces/list-in-organization" do
    with_aggressive_client_timeouts do

      org = find_org!

      control_access :list_codespaces_for_org_public,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Which repos under the org have codespaces?
      repo_ids = Codespace.select(:repository_id).for_organization(org).distinct.pluck(:repository_id)

      # Which repos are accessible to the user and token?

      # rubocop:disable Lint/UnusedBlockArgument
      allowed_repo_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: current_user,
        repository_ids:  repo_ids,
        resource: "codespaces",
        augmentation: -> (actor:, repository_ids:, resource:, accessible_repository_ids:) {
          # Add forks, but not forks of forks
          accessible_repository_ids + Repository.where(parent_id: accessible_repository_ids).pluck(:id)
        }
      )
      # rubocop:enable Lint/UnusedBlockArgument

      # Load full codespace records for permitted repos
      codespaces = Codespace.not_deprovisioning.
        for_organization(org).
        where(repository_id: allowed_repo_ids).
        preload([:owner, :billable_owner]).
        order(id: :asc)
      codespaces = paginate_rel(codespaces)

      deliver :public_codespaces_hash, {
        codespaces: codespaces,
        total_count: codespaces.total_entries
      }, private: FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
    end
  end

  get "/organizations/:organization_id/members/:user_id/codespaces", operation_id: "codespaces/get-codespaces-for-user-in-org" do
    with_aggressive_client_timeouts do
      org = find_org!
      user = find_user!

      control_access :list_codespaces_for_org_public,
        resource: org,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      codespaces, _ = find_codespaces(
        owner: user,
        actor: current_user,
        organization: org,
        filtering_resource: "codespaces",
        include_hidden: true,
      ) || deliver_error!(404)
      codespaces = paginate_rel(codespaces)

      deliver :public_codespaces_hash, {
        codespaces: codespaces,
        total_count: codespaces.total_entries
      }, private: FeatureFlag.vexi.enabled?(:codespaces_developer, current_user, default: false)
    end
  end

  delete "/organizations/:organization_id/members/:user_id/codespaces/:codespace_name", operation_id: "codespaces/delete-from-organization" do
    org = find_org!
    user = find_user!

    codespace = find_codespace(
      owner: user,
      actor: current_user,
      name: params[:codespace_name],
      organization: org,
      filtering_resource: "codespaces",
      include_hidden: true
    ) || deliver_error!(404)

    control_access :delete_codespaces_for_org_public,
      resource: org,
      codespace: codespace,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    codespace.deprovision!(reason: Codespace.deletion_reasons[:org_admin_requested])
    deliver_empty(status: 202)
  end

  post "/organizations/:organization_id/members/:user_id/codespaces/:codespace_name/stop", operation_id: "codespaces/stop-in-organization" do
    org = find_org!
    user = find_user!

    codespace = find_codespace(
      owner: user,
      name: params[:codespace_name],
      organization: org,
      filtering_resource: "codespaces",
      include_hidden: true,
    ) || deliver_error!(404)

    control_access :update_codespace_lifecycle_admin_for_org_public,
      resource: org,
      codespace: codespace,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    stop_codespace(codespace)
  end

  get "/organizations/:organization_id/codespaces/access", operation_id: "codespaces/get-codespaces-access" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:codespaces_org_api_access_users, current_user, default: false)

    control_access :read_user_permissions_for_codespaces_in_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    visibility, selected_usernames = Codespaces::OrgPolicy.billing_policy_members(org)

    deliver :codespaces_billing_policy, {
      visibility: visibility,
      selected_usernames: selected_usernames,
    }
  end

  put "/organizations/:organization_id/codespaces/access", operation_id: "codespaces/set-codespaces-access" do
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:codespaces_org_api_access_users, current_user, default: false)

    data = receive_with_openapi

    control_access :update_user_permissions_for_codespaces_in_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    visibility = data["visibility"]

    if visibility == SELECTED_MEMBERS && data["selected_usernames"].nil?
      deliver_error!(400, message: "`selected_usernames`` is required when when `visibility` is `selected_members`.")
    end
    result = ::Codespaces::ProcessOrganizationEnablementChange.new(
      organization: org,
      actor: current_user,
      enablement: LIMIT_MAPPING[visibility],
      users_to_update: data["selected_usernames"] || [],
    ).call

    limit_updated = result.limit_updated

    if result.selected_users_or_teams_updated || limit_updated
      deliver_empty(status: 204)
    else
      deliver_empty(status: 304)
    end

  rescue ::Codespaces::ProcessOrganizationEnablementChange::UnknownUsersError
    deliver_error!(400, message: "Users are neither members nor collaborators of this organization.")
  rescue ::Codespaces::ProcessOrganizationEnablementChange::InvalidEnablementError
    deliver_error!(422, message: "Invalid visibility was provided.")
  rescue ::Codespaces::ProcessOrganizationEnablementChange::GrantFailedError, Codespaces::ProcessOrganizationEnablementChange::RevokeFailedError => e
    deliver_error!(422, message: e.message)
  end

  post "/organizations/:organization_id/codespaces/access/selected_users", operation_id: "codespaces/set-codespaces-access-users" do
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:codespaces_org_api_access_users, current_user, default: false)
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    data = receive_with_openapi

    control_access :update_user_permissions_for_codespaces_in_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if org.organization_codespaces_user_limit != Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS
      deliver_error!(422, message: "Organization access setting must be set to 'Specific Users' to update specific users.")
    end

    users = org.members.where(login: data["selected_usernames"]) + org.outside_collaborators.where(login: data["selected_usernames"])

    affected_users = grant_access_for_users(users, org)

    if affected_users.any?
      deliver_empty(status: 204)
    else
      deliver_empty(status: 304)
    end
  end

  delete "/organizations/:organization_id/codespaces/access/selected_users", operation_id: "codespaces/delete-codespaces-access-users" do
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:codespaces_org_api_access_users, current_user, default: false)
    org = find_org!
    deliver_error! 404 unless org.codespaces_feature_enabled?

    data = receive_with_openapi

    control_access :update_user_permissions_for_codespaces_in_org,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    if org.organization_codespaces_user_limit != Configurable::OrganizationCodespacesUserLimit::SELECTED_USERS
      deliver_error!(422, message: "Organization billing setting must be set to 'Specific Users' to delete specific users.")
    end

    users = org.members.where(login: data["selected_usernames"]) + org.outside_collaborators.where(login: data["selected_usernames"])

    affected_users = revoke_access_for_users(users, org)

    if affected_users.any?
      deliver_empty(status: 204)
    else
      deliver_empty(status: 304)
    end
  end

  def grant_access_for_users(users, org)
    deliver_error!(400, message: "Users are neither members nor collaborators of this organization.") if users.blank?
    successful_users = []
    failed_users = []

    users.each do |user|
      begin
        has_creator_role = UserRole.find_by(
          actor: user,
          target_id: org.id,
          target_type: "Organization",
          role: Role.codespace_org_creator_role.id
        )

        next if has_creator_role
        Codespaces::OrgPolicy.grant_billing_permission!(user, org)
        GlobalInstrumenter.instrument("codespaces.org_enabled", { organization: org })
        Codespaces::OrgSettingsChangedJob.perform_later(context: user.id, event_type: Codespaces::Events::ORG_CODESPACES_ENABLED_USER, actor_id: user.id)

        successful_users << user
      rescue Codespaces::OrgPolicy::RoleGranterError
        failed_users << user
      end
    end

    if failed_users.any?
      deliver_error!(422, message: "Failed to grant access for the following users: #{failed_users.map(&:login_for_api).join(', ')}")
    else
      successful_users
    end
  end

  def revoke_access_for_users(users, org)
    successful_users = []
    failed_users = []

    users.each do |user|
      begin
        has_creator_role = UserRole.find_by(
          actor: user,
          target_id: org.id,
          target_type: "Organization",
          role: Role.codespace_org_creator_role.id
        )

        next if !has_creator_role
        Codespaces::OrgPolicy.revoke_billing_permission!(user, org)
        Codespaces::OrgSettingsChangedJob.perform_later(context: user.id, event_type: Codespaces::Events::ORG_CODESPACES_DISABLED_USER, actor_id: user.id)

        successful_users << user
      rescue Codespaces::OrgPolicy::RoleGranterError
        failed_users << user
      end
    end

    if failed_users.any?
      deliver_error!(422, message: "Failed to revoke access for the following users: #{failed_users.map(&:login_for_api).join(', ')}")
    else
      successful_users
    end
  end
end
