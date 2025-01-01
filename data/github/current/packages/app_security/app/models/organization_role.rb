# typed: true
# frozen_string_literal: true

class OrganizationRole < Role
  BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT = 10
  ENTERPRISE_CUSTOM_ORG_ROLE_LIMIT = 10
  FILTER_FIELDS = [:role, :is]
  SYSTEM_ROLE_METADATA = T.let({
    all_repo_read: {
      display_name: "All-repository read",
      description: "Grants read access to all repositories in the organization.",
      octicon: "book"
    },
    all_repo_triage: {
      display_name: "All-repository triage",
      description: "Grants triage access to all repositories in the organization.",
      octicon: "checklist"
    },
    all_repo_write: {
      display_name: "All-repository write",
      description: "Grants write access to all repositories in the organization.",
      octicon: "pencil"
    },
    all_repo_maintain: {
      display_name: "All-repository maintain",
      description: "Grants maintenance access to all repositories in the organization.",
      octicon: "tools"
    },
    all_repo_admin: {
      display_name: "All-repository admin",
      description: "Grants admin access to all repositories in the organization.",
      octicon: "eye"
    },
    ci_cd_admin: {
      display_name: "CI/CD Admin",
      description: "Grants admin access to manage Actions policies, runners, runner groups, network configurations, secrets, variables, and usage metrics for an organization.",
      octicon: "play"
    },
    security_manager: {
      display_name: "Security manager",
      description: "Grants the ability to manage security policies, security alerts, and security configurations for an organization and all its repositories.",
      octicon: "shield"
    }
  }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

  VALID_BASE_ROLES = (VALID_REPO_BASE_ROLES + %w(admin)).freeze

  validate :org_limit_for_roles, on: :create
  validate :role_has_base_role_if_repo_fgps_exist

  scope :custom_roles_for_org, ->(org) { where(owner_type: "Organization", owner_id: org&.id) }
  scope :custom_roles_from_business, ->(business) { where(owner_type: "Business", owner_id: business&.id) }
  scope :custom_roles_for_owner, ->(owner) { where(owner_type: owner&.class&.name, owner_id: owner&.id) }
  scope :visible_preset_roles, ->(owner) { presets.where(name: visible_preset_role_names(owner)) }

  def self.sti_name
    "Organization"
  end

  def self.custom_role_by_name(name, owner:)
    return unless owner.organization?
    custom_roles_for_org(owner).find_by(name: name)
  end

  # Public: returns the organization roles assigned to the target.
  #
  # target: either Team or User
  # org: the Organization object
  #
  # Returns an ActiveRecord scope.
  sig { params(actor: T.any(User, Team), org: Organization).returns(ActiveRecord::Relation).checked(:always).on_failure(:raise) }
  def self.assignments_for(actor:, org:)
    scope = case actor
    when User
      UserRole.where(target_type: "Organization", target_id: org.id, actor_type: "User", actor_id: actor.id).pluck(:role_id)
    when Team
      UserRole.where(target_type: "Organization", target_id: org.id, actor_type: "Team", actor_id: actor.id_and_ancestor_ids).pluck(:role_id)
    end

    Role.where(id: scope)
  end

  # Public: returns the repository roles that target has assigned to them, for repositories within the organization.
  #
  # target: either Team or User
  # org: the Organization object
  #
  # Returns a set of Roles
  def self.repository_roles_for(actor:, org:)
    actor_type = case actor when User then "User" when Team then "Team" end

    repo_ids = Repository.active.where(organization_id: org.id).pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
    return [] if repo_ids.empty?

    batched_repo_ids = repo_ids.uniq.in_groups_of(1_000, false)
    all_roles = batched_repo_ids.map do |ids|
      assigned_roles = UserRole.where(actor_type: actor_type, actor_id: actor.id, target_type: "Repository", target_id: ids).pluck(:role_id)
      Role.where(id: assigned_roles)
    end

    all_roles.flatten.uniq
  end

  # Public: The allowed target types for permissions assignments.
  #
  # Returns an array of strings.
  def allowed_permissions_types
    has_base_role? ? [target_type, "Repository"] : [target_type]
  end

  # Public: Returns the action rank for this role.
  # Action rank is only available for Organization Roles with a base role or for read/triage/write/maintain/admin.
  # We should not have other Organization Roles anyways.
  # Returns a Float or nil.
  def action_rank
    Ability::ACTION_RANKING[Role.base_role_ids_to_name[base_role_id]&.to_sym]
  end

  # Public: Returns the name of the base role for an Organization Role
  # Returns a String or nil
  def action_name
    return if base_role_id.nil?
    Role.base_role_ids_to_name[base_role_id]
  end

  # Public: is the first role greater than or equal to the other?
  # Only all repo roles can be compared.
  # Returns a Boolean
  def target_greater_than_or_equal_to_other_role?(other_role:)
    if has_base_role?
      Ability::ACTION_RANKING.fetch(base_role&.name&.to_sym, 0) >= Ability::ACTION_RANKING.fetch(other_role&.to_sym, 0)
    else
      raise "No base role available to compare."
    end
  end

  # Public: is the first role greater than the other?
  # Only all repo roles can be compared.
  # Returns a Boolean
  def target_greater_than_other_role?(other_role:)
    if has_base_role?
      Ability::ACTION_RANKING.fetch(base_role&.name&.to_sym, 0) > Ability::ACTION_RANKING.fetch(other_role&.to_sym, 0)
    else
      raise "No base role available to compare."
    end
  end

  # Public: The number of custom roles a given owner can create.
  sig { params(owner: T.any(Organization, Business)).returns(Integer) }
  def self.custom_role_limit_for_owner(owner)
    # GHES don't have business_plus plans
    return ENTERPRISE_CUSTOM_ORG_ROLE_LIMIT if !GitHub.billing_enabled?

    case owner.plan
    when GitHub::Plan.business_plus
      BUSINESS_PLUS_CUSTOM_ORG_ROLE_LIMIT
    else
      0
    end
  end

  sig { params(org: Organization).returns(Integer) }
  def self.custom_role_limit_for_org(org)
    custom_role_limit_for_owner(org)
  end

  def org_limit_for_roles
    return if preset?

    custom_role_count = OrganizationRole.custom_roles_for_owner(owner).count
    custom_role_limit = OrganizationRole.custom_role_limit_for_owner(owner)

    if owner.custom_roles_supported? && custom_role_count >= custom_role_limit
      errors.add(:owner, "is already at the maximum number of custom roles")
    end
  end

  def role_has_base_role_if_repo_fgps_exist
    unless has_base_role?
      repo_actions = Permissions::FineGrainedPermissionIm.where(target_type: "Repository").map { |fgp| fgp.action }
      has_fgps = permissions.where(action: repo_actions).any?

      if has_fgps
        errors.add(:base_role_id, "must be set if you want to grant permissions to repositories")
      end
    end
  end

  def self.all_repo_read_role
    presets.find_by(name: "all_repo_read")
  end

  def self.all_repo_triage_role
    presets.find_by(name: "all_repo_triage")
  end

  def self.all_repo_write_role
    presets.find_by(name: "all_repo_write")
  end

  def self.all_repo_maintain_role
    presets.find_by(name: "all_repo_maintain")
  end

  def self.all_repo_admin_role
    presets.find_by(name: "all_repo_admin")
  end

  def self.ci_cd_admin_role
    presets.find_by(name: "ci_cd_admin")
  end

  # Public: Checks if custom role dependencies are deleted
  #
  # Returns a Boolean.
  def all_dependencies_updated?
    raise Role::CustomRoleError.new("not a custom role") unless custom?
    !UserRole.where(actor_type: %w[User Team], target_type: target_type, role_id: id).exists?
  end

  # Public: Parses query for organization roles for filters that we allow
  # Will omit any fields that are not in FILTER_FIELDS
  #
  # - query: the query string
  #
  # Returns an Hash containing the parsed query params.
  def self.parse_query(query)
    parsed_query_params = Search::ParsedQuery.parse(query, terms: FILTER_FIELDS)

    query_hash = {}
    parsed_query_params.each do |key, value|
      if value.nil? # the key is just a string (e.g. "foo") - this is the default query
        query_hash[:query] = key
        next
      end
      query_hash[key] = value
    end

    query_hash
  end

  # Public: Stringifies query hash for organization roles
  # Will omit any keys that are not in FILTER_FIELDS
  #
  # - query_hash: Hash with values to be stringified
  #
  # Returns an string that can be used as a query string.
  def self.stringify_query_hash(query_hash)
    query_array = query_hash.filter_map do |key, value|
      if key == :query
        value
      elsif FILTER_FIELDS.include?(key) && !value.nil?
        # if the value of the filter is nil, we can omit it
        [key, value]
      end
    end

    Search::ParsedQuery.stringify(query_array)
  end

  sig { params(owner: T.any(Organization, Business)).returns(T::Array[Symbol]) }
  def self.visible_preset_role_names(owner)
    visible_roles = []

    # The following roles are grouped as "All Preset Roles".
    visible_roles.concat preset_roles_order(owner)
    visible_roles
  end

  sig { params(owner: Organization).returns(T::Array[Role]) }
  def self.visible_roles(owner)
    visible_roles =  self.sorted_visible_preset_roles(owner)
    visible_roles += self.custom_roles_for_org(owner).sort_by(&:name)
    if owner.business&.feature_enabled?(:enterprise_custom_organization_roles)
      visible_roles += custom_roles_from_business(owner.business).sort_by(&:name)
    end
    visible_roles
  end

  def self.sorted_visible_preset_roles(owner)
    visible_preset_roles(owner).sort_by do |role|
      if preset_roles_order(owner).include?(role.name)
        [0, preset_roles_order(owner).index(role.name)]
      else
        [1, role.display_name]
      end
    end
  end

  def self.org_roles_with_repo_access(owner)
    OrganizationRole.visible_roles(owner).select do |role|
      role.base_role_id
    end
  end

  private_class_method def self.preset_roles_order(owner = nil)
    roles = %w(
      all_repo_read
      all_repo_write
      all_repo_triage
      all_repo_maintain
      all_repo_admin
      ci_cd_admin
    )

    roles << "security_manager" if SecurityCenter::FeatureFlagHelper.show_security_manager_in_org_role_assignment?(actor: owner)

    roles
  end

  # Public: Returns the name of the role formatted for display to users.
  # For custom roles, no change to the role name is made.
  # The names of system and internal roles are capitalized unless a custom name is defined in SYSTEM_ROLE_METADATA.
  #
  # Returns a String.
  sig { returns(String) }
  def display_name
    return name if custom?

    SYSTEM_ROLE_METADATA.dig(name.to_sym, :display_name) || name.capitalize
  end

  # Public: Returns the description of the role
  #
  # Returns a String or nil if no description is available.
  sig { returns(T.nilable(String)) }
  def description
    return super if custom?

    SYSTEM_ROLE_METADATA.dig(name.to_sym, :description) || super
  end

  # Public: Returns the octicon for the role
  # If no octicon is defined, the default "note" octicon is returned.
  #
  # Returns a String.
  sig { returns(String) }
  def octicon
    SYSTEM_ROLE_METADATA.dig(name.to_sym, :octicon) || "note"
  end

  private

  def can_create_custom_roles
    return if preset?
    return if owner&.custom_roles_supported?

    if owner.is_a?(Business)
      # return error for enterprises not enabled for custom org roles
      errors.add(:owner, "Enterprises cannot create Custom Roles")
      return
    end
    errors.add(:owner, "does not have the correct plan to create custom roles")
  end

  def valid_base_role
    return if base_role_id.nil?
    return if preset?

    base_role = Role.find_by(id: base_role_id)
    return if base_role && VALID_BASE_ROLES.include?(base_role.name)

    errors.add(:base_role_id, "must be one of: #{VALID_BASE_ROLES.join(", ")}")
  end

  def permissions_descriptions(fgps)
    return "None" if fgps.empty?

    descriptions = fgps.map do |fgp|
      description = OrgFgpMetadata.description_for(fgp.to_sym)
      if description == "unknown"
        # also check for repo level perms
        description = RepoFgpMetadata.description_for(fgp.to_sym)
      end
      description
    end

    descriptions.to_sentence
  end
end
