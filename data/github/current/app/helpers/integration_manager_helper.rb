# typed: true
# frozen_string_literal: true

module IntegrationManagerHelper
  def grant_management_of_all_organization_integrations(user:, organization:, entry_point:)
    role_result = Permissions::Granters::RoleGranter.new(
      actor: user,
      target: organization,
      role: Role.app_manager_role,
    ).grant_unless_exists!

    GitHub.dogstats.increment("integrations.grant_app_manager_role", tags: ["success:true", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
    role_result
  rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
    GitHub.logger.info(
      "Failed to grant app manager role to user",
      "gh.granter_error.message" => role_granter_error.message,
      "gh.organization_id" => organization.id,
      "gh.user_id" => user.id,
    )
    GitHub.dogstats.increment("integrations.grant_app_manager_role", tags: ["success:false", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
    Permissions::Granters::RoleGrantResult.failure!(reason: role_granter_error.message)
  end

  def grant_management_of_integration(user:, integration:, entry_point:)
    role_result = Permissions::Granters::RoleGranter.new(
      actor: user,
      target: integration,
      role: Role.app_owner_role,
    ).grant_unless_exists!

    GitHub.dogstats.increment("integrations.grant_app_owner_role", tags: ["success:true", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: integration.owner)
    role_result
  rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
    GitHub.logger.info(
      "Failed to grant app owner role to user",
      "gh.granter_error.message" => role_granter_error.message,
      "gh.integration_id" => integration.id,
      "gh.user_id" => user.id,
    )
    GitHub.dogstats.increment("integrations.grant_app_owner_role", tags: ["success:false", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: integration.owner)
    Permissions::Granters::RoleGrantResult.failure!(reason: role_granter_error.message)
  end

  def revoke_management_of_all_organization_integrations(user:, organization:, entry_point:)
    role_result = Permissions::Granters::RoleGranter.new(
      actor: user,
      target: organization,
      role: Role.app_manager_role,
    ).revoke_if_exists!

    GitHub.dogstats.increment("integrations.revoke_app_manager_role", tags: ["success:true", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
    role_result
  rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
    GitHub.logger.info(
      "Failed to revoke app manager role of user",
      "gh.granter_error.message" => role_granter_error.message,
      "gh.organization_id" => organization.id,
      "gh.user_id" => user.id,
    )
    GitHub.dogstats.increment("integrations.revoke_app_manager_role", tags: ["success:false", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
    Permissions::Granters::RoleGrantResult.failure!(reason: role_granter_error.message)
  end

  def revoke_management_of_integration(user:, integration:, entry_point:)
    role_result = Permissions::Granters::RoleGranter.new(
      actor: user,
      target: integration,
      role: Role.app_owner_role,
    ).revoke_if_exists!

    GitHub.dogstats.increment("integrations.revoke_app_owner_role", tags: ["success:true", "class:#{user.class.name}"])  if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: integration.owner)
    role_result
  rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
    GitHub.logger.info(
      "Failed to revoke app owner role of user",
      "gh.granter_error.message" => role_granter_error.message,
      "gh.integration_id" => integration.id,
      "gh.user_id" => user.id,
    )
    GitHub.dogstats.increment("integrations.revoke_app_owner_role", tags: ["success:false", "class:#{user.class.name}"]) if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: integration.owner)
    Permissions::Granters::RoleGrantResult.failure!(reason: role_granter_error.message)
  end
end
