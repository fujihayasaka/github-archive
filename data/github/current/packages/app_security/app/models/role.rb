# typed: true
# frozen_string_literal: true

class Role < ApplicationRecord::Iam
  class CustomRoleError < StandardError; end
  class Error < StandardError; end
  class FGPsNotSupportedError < ArgumentError; end
  class InvalidPermissionError < ArgumentError; end
  class InvalidCustomRoleError < ArgumentError; end

  include GitHub::Memoizer
  include Instrumentation::Model

  self.inheritance_column = :target_type

  def self.sti_class_for(type_name)
    case type_name
    when RepositoryRole.sti_name
      RepositoryRole
    when OrganizationRole.sti_name
      OrganizationRole
    when EnterpriseRole.sti_name
      EnterpriseRole
    else
      Role
    end
  end

  extend GitHub::Encoding
  force_utf8_encoding :name, :description

  RESERVED_NAMES = %w(
    triage
    maintain
    read
    write
    admin
  )
  RESERVED_AND_LEGACY_NAMES = RESERVED_NAMES + %w[push pull]

  ALL_REPO_ROLES = %w(
    all_repo_read
    all_repo_triage
    all_repo_write
    all_repo_maintain
    all_repo_admin
  )

  CI_CD_ADMIN_SYSTEM_ROLE = %w(ci_cd_admin)

  PREDEFINED_TYPE = "Predefined"

  PLAN_PROTECTED_ROLES = %w[triage maintain octoshift_migrator]
  SECURITY_SYSTEM_ROLES = %w(enterprise_security_manager security_manager vulnerability_reporter)

  CODESPACES_SYSTEM_ROLES = %w(codespace_org_creator)

  OCTOSHIFT_SYSTEM_ROLES = %w(octoshift_migrator)

  PACKAGES_SYSTEM_ROLES = %w(
    package_reader
    package_writer
    package_admin
  )

  TEAMS_SYSTEM_ROLES = %w(team_writer)

  MEMEX_PROJECTS_SYSTEM_ROLES = %w(
    project_reader
    project_writer
    project_admin
  )

  RULES_SYSTEM_ROLES = %w(
    ref_rules_manager
  )

  CUSTOM_PROPERTIES_SYSTEM_ROLES = %w(
    custom_properties_org_definitions_manager
    custom_properties_org_values_editor
  )

  INTEGRATION_MANAGEMENT_SYSTEM_ROLES = %w(
    app_manager
    app_owner
    enterprise_app_manager
  )

  CUSTOM_COPILOT_ROLES = %w(
    custom_copilot_reader
    custom_copilot_writer
    custom_copilot_admin
  )

  SPARK_ROLES = %w(
    spark_viewer
  )

  INTERNAL_ROLES = PACKAGES_SYSTEM_ROLES + CODESPACES_SYSTEM_ROLES + TEAMS_SYSTEM_ROLES + OCTOSHIFT_SYSTEM_ROLES +
    MEMEX_PROJECTS_SYSTEM_ROLES + RULES_SYSTEM_ROLES + SECURITY_SYSTEM_ROLES + CUSTOM_PROPERTIES_SYSTEM_ROLES +
    INTEGRATION_MANAGEMENT_SYSTEM_ROLES + CUSTOM_COPILOT_ROLES + SPARK_ROLES

  SYSTEM_ROLES = RESERVED_NAMES + INTERNAL_ROLES + ALL_REPO_ROLES + CI_CD_ADMIN_SYSTEM_ROLE

  USER_OWNED_ROLES = PACKAGES_SYSTEM_ROLES + MEMEX_PROJECTS_SYSTEM_ROLES + ["vulnerability_reporter"] + CUSTOM_COPILOT_ROLES + SPARK_ROLES

  BASE_ACTION_FOR_ROLE = { read: :triage, write: :maintain }
  VALID_REPO_BASE_ROLES = %w(read triage write maintain)
  PRIMARY_REPO_BASE_ROLES = %w(read write admin)
  BASE_ROLE_TO_ABILITY = {
    "read": :read,
    "triage": :read,
    "write": :write,
    "maintain": :write,
  }.with_indifferent_access
  VALID_OWNER_TYPES = %w(Organization Business).freeze

  validates :name, presence: true,
            uniqueness: {
              scope: [:owner_id, :owner_type],
              case_sensitive: true
            },
            length: { maximum: 62, too_long: "cannot be longer than %{count} characters" }
  validates :owner, presence: true, unless: :preset?
  validates :owner_type, inclusion: VALID_OWNER_TYPES, allow_nil: true
  validate :disallow_reserved_names
  validate :can_create_custom_roles
  validate :valid_base_role
  validate :description_length

  # owner can be an organization or repo
  belongs_to :owner, polymorphic: true
  has_many :user_roles, dependent: :destroy
  has_many :permissions, class_name: "RolePermission", dependent: :destroy
  belongs_to :base_role, class_name: "Role", foreign_key: "base_role_id" # rubocop:todo Rails/InverseOf

  scope :presets, -> { where(owner_type: nil, owner_id: nil) }
  scope :custom_roles_for_org, ->(org) { where(owner_type: "Organization", owner_id: org&.id) }
  scope :custom_roles_for_enterprise, ->(enterprise) { where(owner_type: "Business", owner_id: enterprise&.id) }

  # scopes fetching internal roles must rely on the preset scope.
  # Custom Roles may have the same name as internal roles,
  # The differentiator is that a custom role always has an owner, an internal role never has an owner.
  scope :system_package_roles, -> { presets.where("name IN (?)", PACKAGES_SYSTEM_ROLES) }
  scope :system_project_roles, -> { presets.where("name IN (?)", MEMEX_PROJECTS_SYSTEM_ROLES) }
  scope :system_repo_roles, -> { presets.where("name IN (?)", RESERVED_NAMES) }
  scope :primary_system_repo_roles, -> { presets.where("name IN (?)", PRIMARY_REPO_BASE_ROLES) }

  after_create_commit  :instrument_create
  after_destroy_commit :instrument_destroy
  after_update_commit :instrument_update
  before_update :old_role_permissions

  after_commit :clear_permissions_cache

  # Public: The preset read role.
  #
  # Returns a Role.
  sig { returns(Role) }
  def self.read_role
    async_read_role.sync
  end

  # Public: The preset triage role.
  #
  # Returns a Role.
  sig { returns(Role) }
  def self.triage_role
    async_triage_role.sync
  end

  # Public: The preset write role.
  #
  # Returns a Role.
  sig { returns(Role) }
  def self.write_role
    async_write_role.sync
  end

  # Public: The preset maintain role.
  #
  # Returns a Role.
  sig { returns(Role) }
  def self.maintain_role
    async_maintain_role.sync
  end

  # Public: The preset admin role.
  #
  # Returns a Role.
  sig { returns(Role) }
  def self.admin_role
    async_admin_role.sync
  end

  # Public: The internal team_writer role.
  #
  # Returns a Role.
  def self.team_writer_role
    presets.find_by(name: "team_writer")
  end

  # Public: The internal octoshift_migrator role.
  #
  # Returns a Role.
  def self.octoshift_migrator_role
    presets.find_by(name: "octoshift_migrator")
  end

  # Public: The internal codespace_org_creator role.
  #
  # Returns a Role.
  def self.codespace_org_creator_role
    presets.find_by(name: ::Codespaces::OrgPolicy::CODESPACE_ORG_CREATOR_ROLE)
  end

  # Public: The internal ref_rules_manager role.
  #
  # Returns a Role.
  def self.ref_rules_manager_role
    presets.find_by(name: "ref_rules_manager")
  end

  # Public: The internal custom_properties_organization_definitions_manager role.
  #
  # Returns a Role.
  def self.custom_properties_org_definitions_manager_role
    presets.find_by(name: "custom_properties_org_definitions_manager")
  end

  # Public: The internal custom_properties_organization_values_editor role.
  #
  # Returns a Role.
  def self.custom_properties_org_values_editor_role
    presets.find_by(name: "custom_properties_org_values_editor")
  end

  # Public: The internal package_reader role.
  #
  # Returns a Role.
  def self.package_reader_role
    presets.find_by(name: "package_reader")
  end

  # Public: The internal package_writer role.
  #
  # Returns a Role.
  def self.package_writer_role
    presets.find_by(name: "package_writer")
  end

  # Public: The internal package_admin role.
  #
  # Returns a Role.
  def self.package_admin_role
    presets.find_by(name: "package_admin")
  end

  # Public: The internal project_reader role.
  #
  # Returns a Role.
  def self.project_reader_role
    presets.find_by(name: "project_reader")
  end

  # Public: The internal project_writer role.
  #
  # Returns a Role.
  def self.project_writer_role
    presets.find_by(name: "project_writer")
  end

  # Public: The internal project_admin role.
  #
  # Returns a Role.
  def self.project_admin_role
    presets.find_by(name: "project_admin")
  end

  # Public: The internal enterprise_security_manager role.
  #
  # Returns a Role.
  def self.enterprise_security_manager_role
    presets.find_by(name: "enterprise_security_manager")
  end

  # Public: The internal security_manager role.
  #
  # Returns a Role.
  def self.security_manager_role
    presets.find_by(name: "security_manager")
  end

  # Public: The internal app_manager role.
  #
  # Returns a Role.
  def self.app_manager_role
    presets.find_by(name: "app_manager")
  end

  # Public: The internal app_owner role.
  #
  # Returns a Role.
  def self.app_owner_role
    presets.find_by(name: "app_owner")
  end

  # Public: The internal enterprise_app_manager role.
  #
  # Returns a Role.
  def self.enterprise_app_manager_role
    presets.find_by(name: "enterprise_app_manager")
  end

  # Public: The internal custom_copilot_reader role.
  #
  # Returns a Role.
  def self.custom_copilot_reader_role
    presets.find_by(name: "custom_copilot_reader")
  end

  # Public: The internal custom_copilot_writer role.
  #
  # Returns a Role.
  def self.custom_copilot_writer_role
    presets.find_by(name: "custom_copilot_writer")
  end

  # Public: The internal custom_copilot_admin role.
  #
  # Returns a Role.
  def self.custom_copilot_admin_role
    presets.find_by(name: "custom_copilot_admin")
  end

  # Public: The internal spark_viewer role.
  #
  # Returns a Role.
  def self.spark_viewer_role
    presets.find_by(name: "spark_viewer")
  end

  # Public: The preset read role.
  #
  # Returns a Promise<Role>.
  def self.async_read_role
    Platform::Loaders::Permissions::PresetRole.load(name: "read")
  end

  # Public: The preset triage role.
  #
  # Returns a Promise<Role>.
  def self.async_triage_role
    Platform::Loaders::Permissions::PresetRole.load(name: "triage")
  end

  # Public: The preset write role.
  #
  # Returns a Promise<Role>.
  def self.async_write_role
    Platform::Loaders::Permissions::PresetRole.load(name: "write")
  end

  # Public: The preset maintain role.
  #
  # Returns a Promise<Role>.
  def self.async_maintain_role
    Platform::Loaders::Permissions::PresetRole.load(name: "maintain")
  end

  # Public: The preset admin role.
  #
  # Returns a Promise<Role>.
  def self.async_admin_role
    Platform::Loaders::Permissions::PresetRole.load(name: "admin")
  end

  # Public: is the role a valid custom role for the owner
  sig { params(name: T.any(Symbol, String), owner: T.any(Organization, Business)).returns(T::Boolean) }
  def self.valid_custom_role?(name, owner:)
    !!custom_role_by_name(name, owner: owner)
  end

  # or

  sig { params(role_name: T.any(String, Symbol, NilClass)).returns(T::Boolean) }
  def self.valid_system_role?(role_name)
    return false unless role_name
    RESERVED_AND_LEGACY_NAMES.include? clean_action(role_name)
  end

  # Public: is `role_name` a role that's only available to certain billing plans?
  # `triage` and `maintain` are currently the only plan-restricted roles.
  sig { params(role_name: String).returns(T::Boolean) }
  def self.plan_protected_role?(role_name)
    PLAN_PROTECTED_ROLES.include?(role_name)
  end

  # Get the name of the base role for a given role.
  # note that reserved and internal roles do not have a base role, so we return the role name itself.
  sig { params(name: String, owner: T.nilable(Organization)).returns(String) }
  def self.base_role_name_or_self(name, owner: nil)
    # we know reserved roles are unique and have no owner
    # system roles may share a name with custom roles, so we must check the owner is nil.
    # we don't have an owner.nil? check on reserved names because some repository callsites
    # dynamically pass repo names and repo owners. e.g. computing mixed roles.
    base_role = if RESERVED_NAMES.include?(name) || (SYSTEM_ROLES.include?(name) && owner.nil?)
      Role.presets.find_by!(name: name).base_role
    else
      Role.find_by!(name: name, owner_id: T.must(owner).id, owner_type: owner.class.name).base_role
    end

    base_role.present? ? base_role.name : name
  end

  # Public: translates an internal Role exception into a user-friendly message.
  #         supports the following exceptions: Role::FGPsNotSupportedError,
  #         Role::InvalidPermissionError, Role::InvalidCustomRoleError
  #
  # exception: exception to translate
  # permission: permission that triggered the exception
  # repository: repository that the permission was being applied to
  #
  # Returns: String for one of the supported exceptions, nil otherwise.
  def self.error_message_from_exception(exception, permission:, repository:)
    case exception
    when Role::FGPsNotSupportedError
      "Role `#{permission}` is not supported under the current billing plan."
    when Role::InvalidPermissionError
      "`#{permission}` is not a valid permission."
    when Role::InvalidCustomRoleError
      "Role `#{permission}` is not available for the #{repository.name_with_owner} repository."
    end
  end

  # Public: grant the legacy ability
  def self.grant_legacy_permissions(actor, ability, target, role_name: nil)
    Ability.grant(actor, ability, target, role_name: role_name)
  end

  sig { params(name: T.any(Symbol, String, NilClass)).returns(T.nilable(Role)) }
  def self.preset_by_name(name)
    presets.find_by(name: name)
  end

  sig { params(name: T.any(Symbol, String, NilClass)).returns(T.nilable(Role)) }
  def self.internal_role_by_name(name)
    presets.find_by(name: name)
  end

  # Public: Precalculate Hash of base role id to name
  # We need this because the role ids can change per instance and we avoid queries by doing this once
  def self.base_role_ids_to_name
    unless defined?(@base_role_ids_to_name)
      base_role_names = Ability::ACTION_RANKING.keys.map(&:to_s)
      base_roles = Role.presets.where(target_type: "Repository", name: base_role_names)
      @base_role_ids_to_name = base_roles.to_h { |r| [r.id, r.name] }
    end
    @base_role_ids_to_name
  end

  sig { params(name: T.any(Symbol, String), owner: T.any(Organization, Business)).returns(T.nilable(Role)) }
  def self.custom_role_by_name(name, owner:)
    if owner.organization?
      custom_roles_for_org(owner).find_by(name: name)
    elsif owner.business?
      custom_roles_for_enterprise(owner).find_by(name: name)
    end
  end

  # Public: clean a given action/permission name by converting it to a string,
  #         downcasing, and stripping out whitespace.
  #
  # action: string, name of the action/permission
  #
  # Returns: String
  sig { params(action: T.any(String, Symbol, NilClass)).returns(String) }
  def self.clean_action(action)
    action.to_s.downcase.strip
  end

  # returns a the provided role name if it exists as a valid role in the repository
  # it would raise if the role does not exists or is not supported by the current billing plan
  def self.find_role_name!(role_name:, repository:)
    if Role.valid_system_role?(role_name)
      if PLAN_PROTECTED_ROLES.include?(role_name)
        raise ArgumentError, "Role: #{role_name}, is not supported for the current billing plan" unless repository.fine_grained_permissions_supported?
      end

      Repository.permission_to_action(role_name)
    else
      raise ArgumentError, "Role: #{role_name}, is not supported for the current billing plan" unless repository.owner.custom_roles_supported?
      role = Role.find_by!(name: role_name, owner_id: repository.organization.id, owner_type: "Organization")
      role.name
    end
  end

  # Public: Is this role one of the preset roles that we provide?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def preset?
    return false unless owner_type.nil? && owner_id.nil?
    SYSTEM_ROLES.include?(name)
  end

  # Public: Is this role a custom role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def custom?
    !preset? && owner_id.present?
  end

  # Public: Is this role an internal role?
  # Internal roles are system roles (i.e. available system wide, rather than each organization having one),
  # which are not the default 'read/triage/write/maintain/admin'. They are intended to be used for
  # non-repository based permissions.
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def internal?
    preset? && INTERNAL_ROLES.include?(name)
  end

  # Public: Source answers the question, "where did this role come from?"
  # For custom roles, this is the owner type, eg. "Organization" or "Enterprise"
  # For system roles, this returns "Predefined"
  # Returns a String.
  sig { returns(String) }
  def source
    custom? ? T.must(owner_type) : PREDEFINED_TYPE
  end

  # Public: Returns the name of the role formatted for display to users.
  # For custom roles, no change to the role name is made.
  # The names of system and internal roles are capitalized.
  #
  # Returns a String.
  sig { returns(String) }
  def display_name
    return name if custom?
    name.capitalize
  end

  # Public: the fine grained permissions that the role explicitly has
  # which are available for custom roles.
  #
  # Returns an ActiveRecord::Relation of role_permissions.
  def custom_role_permissions
    permissions.custom_roles_enabled
  end

  # Public: Is this role the preset read role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def read?
    return false unless preset?
    name == "read"
  end

  # Public: Is this role the preset triage role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def triage?
    return false unless preset?
    name == "triage"
  end

  # Public: Is this role the preset write role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def write?
    return false unless preset?
    name == "write"
  end

  # Public: Is this role the preset maintain role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def maintain?
    return false unless preset?
    name == "maintain"
  end

  # Public: Is this role the preset admin role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def admin?
    return false unless preset?
    name == "admin"
  end

  # Public: Is this role the preset enterprise security manager role?
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def enterprise_security_manager?
    return false unless preset?
    name == "enterprise_security_manager"
  end

  # Public: Does this role require a special plan type?
  # Triage, Maintain and Custom roles
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def requires_non_legacy_plan?
    return true if PLAN_PROTECTED_ROLES.include?(name)
    return true if custom?

    false
  end

  # Public: The ids of the users assigned the role.
  #
  # Returns an Array of ids.
  sig { returns(T::Array[Integer]) }
  def user_ids
    return @user_ids if defined?(@user_ids)
    @user_ids = user_roles.where(actor_type: "User").pluck(:actor_id)
  end

  # Public: The ids of the org members assigned the role.
  #
  # Returns an Array of ids.
  sig { returns(T::Array[Integer]) }
  def org_member_ids
    return @org_member_ids if defined?(@org_member_ids)
    return [] unless owner.organization?

    org_member_ids = owner.direct_member_ids
    @org_member_ids = user_ids & org_member_ids
  end

  sig { returns(T::Array[Integer]) }
  def collaborator_ids
    return @collab_ids if defined?(@collab_ids)
    return [] unless owner.organization?

    @collab_ids = user_ids - org_member_ids
  end

  # Public: The number of users assigned the role.
  #
  # Returns an Int.
  sig { returns(Integer) }
  def user_count
    user_ids.size
  end

  # Public: The number of org members assigned the role.
  #
  # Returns an Int.
  sig { returns(Integer) }
  def org_member_count
    org_member_ids.size
  end

  # Public: The number of outside collaborators assigned the role.
  #
  # Returns an Int.
  sig { returns(Integer) }
  def collaborator_count
    collaborator_ids.size
  end

  # Public: The number of teams assigned a specific role.
  #
  # Returns an Int.
  sig { returns(Integer) }
  memoize def team_count
    business = owner.is_a?(Business) ? owner : owner&.business
    actor_type = business&.enterprise_teams_org_roles_supported? ? %w(Team BusinessTeam) : %w(Team)
    user_roles.where(actor_type:).size
  end

  # Public: Does the role have a non nil base_role_id
  #
  # Returns a Boolean
  sig { returns(T::Boolean) }
  def has_base_role?
    base_role_id?
  end

  sig { returns(T::Array[String]) }
  def implicit_fgps
    return [] unless base_role
    @implicit_fgps ||= T.must(base_role).permissions.pluck(:action)
  end

  # Public: Checks if custom role dependencies are deleted
  #
  # Returns a Boolean.
  sig { returns(T::Boolean) }
  def all_dependencies_updated?
    raise Role::CustomRoleError.new("not a custom role") unless custom?
    !(
      UserRole.where(actor_type: %w[User Team], target_type: target_type, role_id: id).exists? ||
      RepositoryInvitation.where(role_id: id).exists?
    )
  end

  # Public: The allowed target types for permissions assignments.
  #
  # Returns an array of strings.
  sig { returns(T::Array[String]) }
  def allowed_permissions_types
    [T.must(target_type)]
  end

  # Returns: String
  sig { returns(String) }
  def action_name
    name
  end

  sig { returns(String) }
  def octicon
    "note"
  end

  private

  sig { void }
  def disallow_reserved_names
    return if preset?

    if (RESERVED_NAMES + %w[push pull]).map(&:downcase).include?(Role.clean_action(name))
      errors.add(:name, "is a reserved role name")
    end
  end

  sig { void }
  def can_create_custom_roles
    return if preset?
    return if owner.is_a?(Business) && owner.custom_enterprise_roles_supported?

    if owner.is_a?(Business)
      # return error as long as we don't enable Custom Enterprise Roles
      errors.add(:owner, "Enterprises cannot create Custom Roles")
      return
    end
    return if owner&.custom_roles_supported?
    errors.add(:owner, "does not have the correct plan to create custom roles")
  end

  sig { void }
  def valid_base_role
    return if preset?
    base_role = Role.find_by(id: base_role_id)
    return if base_role && VALID_REPO_BASE_ROLES.include?(base_role.name)
    errors.add(:base_role_id, "selection is invalid")
  end

  sig { void }
  def description_length
    return unless Role.has_attribute?(:description)

    field_length = 152
    if description && description.length > field_length
      errors.add(:description, "cannot be longer than #{field_length} characters")
    end
  end

  sig { void }
  def instrument_create
    instrument :create
  end

  sig { void }
  def instrument_destroy
    instrument :destroy

    return unless custom?

    if self.is_a? RepositoryRole
      GlobalInstrumenter.instrument("custom_repository_roles.role_deleted", {
        role: self,
        org_custom_roles_count: Role.custom_roles_for_org(owner).count
      })
    elsif self.is_a? OrganizationRole
      GlobalInstrumenter.instrument("custom_organization_roles.role_deleted", {
        role: self,
        org_custom_org_roles_count: Role.custom_roles_for_org(owner).count
      })
    elsif self.is_a?(EnterpriseRole) && owner.custom_enterprise_roles_supported?
      GlobalInstrumenter.instrument("custom_enterprise_roles.role_deleted", {
        role: self,
        enterprise_custom_roles_count: Role.custom_roles_for_enterprise(owner).count
      })
    end
  end

  sig { void }
  def instrument_update
    changes_payload = {}.tap do |hash|
      hash[:old_name] = previous_changes["name"].first if name_changed?
      hash[:old_role_permissions] = permissions_descriptions(old_role_permissions) if permissions_changed?
      hash[:old_base_role] = old_base_role if previous_changes["base_role_id"].present?
    end

    return if changes_payload.empty?

    instrument :update, changes: changes_payload

    return unless custom?

    if self.is_a? RepositoryRole
      GlobalInstrumenter.instrument("custom_repository_roles.role_updated", {
        role: self
      })
    elsif self.is_a? OrganizationRole
      GlobalInstrumenter.instrument("custom_organization_roles.role_updated", {
        role: self
      })
    elsif self.is_a?(EnterpriseRole) && owner.custom_enterprise_roles_supported?
      # TODO Add Instrumentation
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      name: name,
      owner: owner&.display_login,
      role_permissions: permissions_descriptions(permissions.pluck(:action)),
      base_role: base_role&.name,
    }

    payload[:old_base_role] = old_base_role if previous_changes["base_role_id"].present? && old_base_role.present?
    payload[:old_role_permissions] = permissions_descriptions(old_role_permissions) if permissions_changed?

    if owner.is_a? Organization
      payload[:org] = owner
      payload[:business] = owner&.business
    end

    if owner.is_a?(Business) && owner.custom_enterprise_roles_supported?
      payload[:business] = owner
    end

    payload
  end

  def clear_permissions_cache
    PermissionCache.clear
  end

  # Internal: the explicit FGPs for this role prior to being updated.
  # Note that this method is called before updating the object.
  #
  # Returns an Array of strings
  sig { returns(T::Array[String]) }
  def old_role_permissions
    return [] unless custom?
    @old_fgps ||= permissions.pluck(:action)
  end

  sig { returns(T::Boolean) }
  def permissions_changed?
    old_role_permissions != permissions.pluck(:action)
  end

  def name_changed?
    return false unless previous_changes["name"].present?
    old, new = previous_changes["name"]
    # we take the binary difference because emoji's not yet persisted will not be binary encoded
    old.b != new.b
  end

  # Internal: the name of the base role prior to being updated.
  #
  # Returns a string
  sig { returns(T.nilable(String)) }
  def old_base_role
    Role.find_by(id: previous_changes["base_role_id"].first)&.name
  end

  # Internal: the human readable sentence of a set of fine grained permissions.
  #
  # - fgps: Array of strings or symbols of the fine grained permission identifiers.
  #
  # Returns a string
  sig { params(fgps: T::Array[String]).returns(String) }
  def permissions_descriptions(fgps)
    return "None" if fgps.empty?

    descriptions = fgps.sort.map { |fgp| RepoFgpMetadata.description_for(fgp.to_sym) }
    descriptions.to_sentence
  end
end
