# typed: true
# frozen_string_literal: true

module CopilotSpace::PermissionsDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  requires_ancestor { CopilotSpace }

  def async_adminable_by?(user)
    return false unless user
    # we need to set the current_user for feature flag checks
    # user will always be the current user in these permission checks.
    self.current_user ||= user

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
    # we need to set the current_user for feature flag checks
    # user will always be the current user in these permission checks.
    self.current_user ||= user

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
    # we need to set the current_user for feature flag checks
    # user will always be the current user in these permission checks.
    self.current_user ||= user

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

  # Update a user's role on this Copilot Space
  # Revokes existing role and grants the new one
  sig { params(actor: T.any(User, Team), role: Role).void }
  def update_user_role!(actor:, role:)
    Permissions::Granters::RoleGranter.new(actor: actor, target: self).revoke_if_exists!
    Permissions::Granters::RoleGranter.new(actor: actor, target: self, role: role).grant_unless_exists!
  end

  # Custom exceptions for collaborator operations
  class CollaboratorError < StandardError; end

  # Add a collaborator to the space, raising descriptive errors
  # @param user_login [String] the login of the user to add
  # @param role_name [String] the name of the role to grant
  # @return [User] the added collaborator
  # @raise [CollaboratorError] if validation or granting fails
  sig { params(user_login: String, role_name: String).returns(User) }
  def add_collaborator!(user_login:, role_name:)
    raise CollaboratorError, "User login is required" if user_login.blank?

    collaborator_user = User.find_by_login(user_login.strip)
    raise CollaboratorError, "User '#{user_login}' not found" unless collaborator_user

    role = CopilotSpaces::RoleMappingHelper.requested_role_by_name(role_name)
    raise CollaboratorError, "Invalid role specified" unless role

    Permissions::Granters::RoleGranter.new(actor: collaborator_user, target: self, role: role).grant!
    collaborator_user
  end

  # Remove a collaborator from this Copilot Space
  # @param actor [User, Team] the actor to remove (if provided)
  # @param user_role_id [Integer] the ID of the UserRole to remove (alternative approach)
  # @return [User, Team] the actor that was removed
  # @raise [CollaboratorError] if validation fails or revocation fails
  sig { params(actor: T.nilable(T.any(User, Team)), user_role_id: T.nilable(Integer)).returns(T.any(User, Team)) }
  def remove_collaborator!(actor: nil, user_role_id: nil)
    # Resolve the actor if not provided directly
    if actor.nil?
      if user_role_id.present?
        # Find actor via user_role_id - use direct query to avoid cached association issues
        user_role = UserRole.find_by(id: user_role_id, target_type: "CustomCopilot", target_id: id)
        raise CollaboratorError, "Collaborator not found" unless user_role
        actor = user_role.actor
      else
        raise CollaboratorError, "Either actor or user_role_id must be provided"
      end
    end

    Permissions::Granters::RoleGranter.new(actor: actor, target: self).revoke_if_exists!
    actor
  end

  # Update a user's role on this Copilot Space using role name
  # @param role_name [String] the name of the new role to assign
  # @param actor [User, Team] the actor whose role to update (if provided)
  # @param user_role_id [Integer] the ID of the UserRole to update (alternative approach)
  # @raise [CollaboratorError] if validation fails
  sig { params(role_name: String, actor: T.nilable(T.any(User, Team)), user_role_id: T.nilable(Integer)).void }
  def update_user_role_by_name!(role_name:, actor: nil, user_role_id: nil)
    # Resolve the actor if not provided directly
    if actor.nil?
      if user_role_id.present?
        # Find actor via user_role_id - use direct query to avoid cached association issues
        user_role = UserRole.find_by(id: user_role_id, target_type: "CustomCopilot", target_id: id)
        raise CollaboratorError, "Collaborator not found" unless user_role
        actor = user_role.actor
      else
        raise CollaboratorError, "Either actor or user_role_id must be provided"
      end
    end

    role = CopilotSpaces::RoleMappingHelper.requested_role_by_name(role_name)
    raise CollaboratorError, "Invalid role specified: #{role_name}" unless role

    update_user_role!(actor: actor, role: role)
  end

  private

  def get_policy_version(user)
    enabled_managed_individual_sharing = FeatureFlag.vexi.enabled?(:copilot_spaces_individual_policies_ga, user, default: false)
    enabled_block_individual_access = FeatureFlag.vexi.enabled?(:copilot_spaces_block_individual_access, user, default: false)

    # Disable public spaces for EMU users and EMU-owned spaces
    enabled_public_spaces = !(user.is_enterprise_managed? || is_enterprise_managed?)

    return 9 if enabled_block_individual_access
    return 8 if enabled_managed_individual_sharing
    return 7 if enabled_public_spaces
    6
  end
end
