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
end
