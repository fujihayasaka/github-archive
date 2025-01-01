# typed: true
# frozen_string_literal: true

module CopilotSpace::PermissionsDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { CopilotSpace }

  def async_adminable_by?(user)
    return false unless user

    policy_version = get_policy_version(user)

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :admin_custom_copilot,
      actor: user,
      subject: self,
      context: { version: policy_version },
    ).then(&:allow?)
  end

  def adminable_by?(user)
    async_adminable_by?(user).sync
  end

  def async_editable_by?(user)
    return false unless user

    policy_version = get_policy_version(user)

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :write_custom_copilot,
      actor: user,
      subject: self,
      context: { version: policy_version },
    ).then(&:allow?)
  end

  def editable_by?(user)
    async_editable_by?(user).sync
  end

  def async_readable_by?(user)
    return false unless user

    policy_version = get_policy_version(user)

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :read_custom_copilot,
      actor: user,
      subject: self,
      context: { version: policy_version },
    ).then(&:allow?)
  end

  def readable_by?(user)
    async_readable_by?(user).sync
  end

  private

  def get_policy_version(user)
    enabled_read_access_to_user_owned_spaces = FeatureFlag.vexi.enabled?(:copilot_spaces_read_access_to_user_owned_spaces, user, default: false)
    enabled_public_spaces = FeatureFlag.vexi.enabled?(:copilot_spaces_public_access_to_user_owned_spaces, user, default: false)

    if enabled_read_access_to_user_owned_spaces
      return enabled_public_spaces ? 5 : 6
    end

    4
  end
end
