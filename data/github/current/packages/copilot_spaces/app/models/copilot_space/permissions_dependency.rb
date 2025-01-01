# typed: true
# frozen_string_literal: true

module CopilotSpace::PermissionsDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { CopilotSpace }

  def async_adminable_by?(user)
    return false unless user

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :admin_custom_copilot,
      actor: user,
      subject: self,
      context: { version: 2 },
    ).then(&:allow?)
  end

  def adminable_by?(user)
    async_adminable_by?(user).sync
  end

  def async_editable_by?(user)
    return false unless user

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :write_custom_copilot,
      actor: user,
      subject: self,
      context: { version: 2 },
    ).then(&:allow?)
  end

  def editable_by?(user)
    async_editable_by?(user).sync
  end

  def async_readable_by?(user)
    return false unless user

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :read_custom_copilot,
      actor: user,
      subject: self,
      context: { version: 2 },
    ).then(&:allow?)
  end

  def readable_by?(user)
    async_readable_by?(user).sync
  end
end
