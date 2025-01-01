# typed: true
# frozen_string_literal: true

module IntegrationManagerHelper
  # Internal: Does this user have permission to manage all integrations for the
  # target (User or Organization).
  #
  # Returns a Boolean.
  def manages_all_integrations?(user:, owner:)
    return false unless owner

    async_manages_all_integrations?(user: user, owner: owner).sync
  end

  def async_manages_all_integrations?(user:, owner:)
    return Promise.resolve(false) unless owner
    return Promise.resolve(owner.adminable_by?(user)) if owner.is_a?(Business)

    Platform::Loaders::Permissions::BatchAuthorize
    .load(
      actor: user,
      action: :manage_all_apps,
      subject: owner,
    )
    .then(&:allow?)
  end

  def manages_integration?(user:, integration:)
    return false unless integration

    ::Permissions::Enforcer.authorize(
      actor: user,
      action: :manage_app,
      subject: integration,
    ).allow?
  end

  def manages_any_integration?(user:, organization:)
    return false unless organization

    return manages_all_integrations?(user: user, owner: organization) if organization.integrations.empty?

    async_manages_any_integration?(user: user, organization: organization).sync
  end

  def async_manages_any_integration?(user:, organization:)
    return Promise.resolve(false) unless organization

    return async_manages_all_integrations?(user: user, owner: organization) if organization.integrations.empty?

    Platform::Loaders::Permissions::BatchAuthorize
    .load(
      action: :manage_any_app,
      actor: user,
      subject: organization,
      context: {
        organization_integrations: organization.integrations.collect(&:id).to_a,
      }
    )
    .then(&:allow?)
  end

  def grant_management_of_all_organization_integrations(user:, organization:, entry_point:)
    if organization.feature_enabled?(:org_app_management_via_fgps)
      begin
        _role_result = Permissions::Granters::RoleGranter.new(
          actor: user,
          target: organization,
          role: Role.app_manager_role,
        ).grant_unless_exists!
      rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
        GitHub.logger.info(
          "Failed to grant app manager role to user",
          "gh.granter_error.message" => role_granter_error.message,
          "gh.organization_id" => organization.id,
          "gh.user_id" => user.id,
        )
      end
    end

    ::Permissions::Granter.grant(
      action: :manage_all_apps,
      actor_id: user.id,
      subject_id: organization.id,
      entry_point: entry_point,
    )
  end

  def grant_management_of_integration(user:, integration:, entry_point:)
    if integration.feature_enabled?(:org_app_management_via_fgps)
      begin
        _role_result = Permissions::Granters::RoleGranter.new(
          actor: user,
          target: integration,
          role: Role.app_owner_role,
        ).grant_unless_exists!
      rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
        GitHub.logger.info(
          "Failed to grant app owner role to user",
          "gh.granter_error.message" => role_granter_error.message,
          "gh.integration_id" => integration.id,
          "gh.user_id" => user.id,
        )
      end
    end

    ::Permissions::Granter.grant(
      action: :manage_app,
      actor_id: user.id,
      subject_id: integration.id,
      entry_point: entry_point,
    )
  end

  def revoke_management_of_all_organization_integrations(user:, organization:, entry_point:)
    if organization.feature_enabled?(:org_app_management_via_fgps)
      begin
        Permissions::Granters::RoleGranter.new(
          actor: user,
          target: organization,
          role: Role.app_manager_role,
        ).revoke_if_exists!
      rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
        GitHub.logger.info(
          "Failed to revoke app manager role of user",
          "gh.granter_error.message" => role_granter_error.message,
          "gh.organization_id" => organization.id,
          "gh.user_id" => user.id,
        )
      end
    end

    ::Permissions::Granter.revoke(
      actor_id: user.id,
      action: :manage_all_apps,
      subject_id: organization.id,
      entry_point: entry_point,
    )
  end

  def revoke_management_of_integration(user:, integration:, entry_point:)
    if integration.feature_enabled?(:org_app_management_via_fgps)
      begin
        Permissions::Granters::RoleGranter.new(
          actor: user,
          target: integration,
          role: Role.app_owner_role,
        ).revoke_if_exists!
      rescue Permissions::Granters::RoleGranter::GrantFailure => role_granter_error
        GitHub.logger.info(
          "Failed to revoke app owner role of user",
          "gh.granter_error.message" => role_granter_error.message,
          "gh.integration_id" => integration.id,
          "gh.user_id" => user.id,
        )
      end
    end

    ::Permissions::Granter.revoke(
      action: :manage_app,
      actor_id: user.id,
      subject_id: integration.id,
      entry_point: entry_point,
    )
  end
end
