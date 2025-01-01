# typed: false
# frozen_string_literal: true

class UserRole < ApplicationRecord::Iam
  include GitHub::BatchedScope

  # Raised if an attempt is made to access the target association where
  # target_type is not an ActiveRecord model. This is expected when a target
  # object is managed by an external application.
  class UnknownTargetClassError < StandardError; end

  VALID_ACTOR_TYPES = %w(Team User)
  CUSTOM_ROLE_TARGET_TYPES = %w(Repository Organization Business)
  VALID_TARGET_TYPES = %w(Business Repository User Organization MemexProject)

  # Assigning an actor to multiple UserRoles with the same target_type is not permitted except for the listed target_types.
  MULTIPLE_ASSIGNMENT_TARGET_TYPES = %w(Business Organization)

  # If the internal role doesn't have a Target Type, it needs to be specified here
  INTERNAL_ROLE_TARGET_TYPE = {
    "ref_rules_manager": "Organization",
    "codespace_org_creator": "Organization",
    "octoshift_migrator": "Organization",
    "custom_properties_org_definitions_manager": "Organization",
    "custom_properties_org_values_editor": "Organization",
    "package_reader": "Package",
    "package_writer": "Package",
    "package_admin": "Package",
    "team_writer": "Team",
    "project_reader": "MemexProject",
    "project_writer": "MemexProject",
    "project_admin": "MemexProject",
    "vulnerability_reporter": "Repository",
  }

  validates :role_id,
            :actor_id,
            :actor_type,
            :target_id,
            :target_type, presence: true
  # An Actor can only be assigned to a single role on a target unless the target_type allows multiple assignments
  validates :actor_id,
    uniqueness: { scope: [:actor_type, :target_id, :target_type] },
    unless: :multiple_roles_on_target_allowed?
  # An Actor can only be assigned to a Role once on a target
  validates :actor_id,
    uniqueness: {
      scope: [:actor_type, :role_id, :target_id, :target_type],
      message: "may not be assigned to a Role more than once on a target"
    },
    if: :multiple_roles_on_target_allowed?
  validate :valid_actor_type
  validate :valid_target_type
  validate :target_plan_supports

  belongs_to :role
  belongs_to :actor, polymorphic: true
  belongs_to :target, polymorphic: true

  after_commit :clear_permissions_cache

  # Public: The name of this role.
  #
  # Returns a String.
  def action_name
    role.name
  end

  # Public: The object this role targets. Raises UnknownTargetClassError
  # if the target is not an ActiveRecord model and its lifecycle is
  # managed by an external application.
  #
  # Returns User, Organization
  def target
    target_type.constantize.find(target_id)
  rescue NameError
    raise UnknownTargetClassError, "Target type `#{target_type}` cannot be accessed as an association."
  end

  private

  def target_plan_supports
    return true unless role.requires_non_legacy_plan?

    target_owner = target.is_a?(User) || target.is_a?(Business) ? target : target.owner
    unless target_owner.plan_supports?(:fine_grained_permissions)
      errors.add(:target, "does not have the necessary plan to grant this role")
    end
  end

  def valid_actor_type
    if role.name == "security_manager"
      if target.is_a?(Organization) && SecurityCenter::FeatureFlagHelper.show_security_manager_in_org_role_assignment?(actor: target)
        return if VALID_ACTOR_TYPES.include?(actor_type)
      else
        return if actor_type == "Team"
      end
    elsif role.name == "enterprise_security_manager"
      return if actor_type == "EnterpriseTeam"
    else
      return if VALID_ACTOR_TYPES.include?(actor_type)
    end

    errors.add(:actor_type, "#{actor_type} is not valid for #{role.name}")
  end

  def valid_target_type
    if role.target_type && role.target_type != target_type
      errors.add(:target_type, "#{target_type} does not match #{role.name}'s target_type: #{role.target_type}")
    end

    return if role.internal? && INTERNAL_ROLE_TARGET_TYPE[role.name.to_sym] == target_type
    return if role.custom?   && CUSTOM_ROLE_TARGET_TYPES.include?(target_type)
    return if role.preset?   && VALID_TARGET_TYPES.include?(target_type)

    errors.add(:target_type, "#{target_type} is not valid for #{role.name}")
  end

  def multiple_roles_on_target_allowed?
    MULTIPLE_ASSIGNMENT_TARGET_TYPES.include?(target_type)
  end

  def clear_permissions_cache
    PermissionCache.clear
  end
end
