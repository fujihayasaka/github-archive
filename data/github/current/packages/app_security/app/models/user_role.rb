# typed: false
# frozen_string_literal: true

class UserRole < ApplicationRecord::Iam
  include GitHub::BatchedScope
  include Authz::IUserRole

  # Raised if an attempt is made to access the target association where
  # target_type is not an ActiveRecord model. This is expected when a target
  # object is managed by an external application.
  class UnknownTargetClassError < StandardError; end

  VALID_ACTOR_TYPES = %w(Team User BusinessTeam)
  CUSTOM_ROLE_TARGET_TYPES = %w(Repository Organization Business)
  VALID_TARGET_TYPES = %w(Business Repository User Organization MemexProject Integration CustomCopilot)

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
    "spark_viewer": "Spark::RuntimeApp",
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

  validates_presence_of :conditions, if: -> { requires_conditions_to_be_granted? }
  validate :valid_conditions

  belongs_to :role
  belongs_to :actor, polymorphic: true
  belongs_to :target, polymorphic: true

  after_commit :clear_permissions_cache

  # Internal: Determine if the user role can be granted to a target
  # that it was not originally intended for.
  def self.requires_conditions_to_be_granted?(role, target)
    return false unless role.is_a?(OrganizationRole)
    return false unless target.is_a?(Business)

    if role.preset? || (role.custom? && role.owner.is_a?(Business))
      return true if target.erp_feature_enabled?(:enterprise_teams_esm)
    end

    false
  end

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
    if target_type == "Repository" && FeatureFlag.vexi.enabled?(:repos_domain_packages, default: false)
      Repositories.domain.by_id(target_id)
    else
      target_type.constantize.find(target_id)
    end
  rescue NameError
    raise UnknownTargetClassError, "Target type `#{target_type}` cannot be accessed as an association."
  end

  def conditions=(value)
    # Serialize the struct instead of calling #to_h so that we drop unused keys.
    if value.is_a?(UserRoleCondition)
      value = value.serialize
    end

    super
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
    if role.name == "enterprise_security_manager"
      return if actor_type == "BusinessTeam" || actor_type == "EnterpriseTeam"
    else
      return if VALID_ACTOR_TYPES.include?(actor_type)
    end

    errors.add(:actor_type, "#{actor_type} is not valid for #{role.name}")
  end

  def valid_target_type
    if role.target_type && role.target_type != target_type
      unless permitted_cross_target_role_grant?
        errors.add(:target_type, "#{target_type} does not match #{role.name}'s target_type: #{role.target_type}")
      end
    end

    return if role.internal? && INTERNAL_ROLE_TARGET_TYPE[role.name.to_sym] == target_type
    return if role.custom?   && CUSTOM_ROLE_TARGET_TYPES.include?(target_type)
    return if role.preset?   && VALID_TARGET_TYPES.include?(target_type)

    errors.add(:target_type, "#{target_type} is not valid for #{role.name}")
  end

  USER_ROLE_CONDITION_SCHEMA_FILE_PATH = "packages/app_security/app/models/user_role_condition/schema.json"

  def valid_conditions
    return if conditions.nil?

    begin
      schema_file_path = Rails.root.join(*(USER_ROLE_CONDITION_SCHEMA_FILE_PATH.split("/"))).to_s
      JSON::Validator.validate!(schema_file_path, conditions.to_json)
    rescue JSON::Schema::ValidationError => e
      errors.add(:conditions, e.message)
    end
  end

  def multiple_roles_on_target_allowed?
    MULTIPLE_ASSIGNMENT_TARGET_TYPES.include?(target_type)
  end

  def clear_permissions_cache
    PermissionCache.clear
  end

  def permitted_cross_target_role_grant?
    conditions.present? && requires_conditions_to_be_granted?
  end

  def requires_conditions_to_be_granted?
    self.class.requires_conditions_to_be_granted?(self.role, self.target)
  rescue ActiveRecord::RecordNotFound, UnknownTargetClassError
    false
  end
end
