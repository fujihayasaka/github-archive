# typed: true
# frozen_string_literal: true

class RepositoryRole < Role

  BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT = 5
  ENTERPRISE_CUSTOM_REPO_ROLE_LIMIT = 5

  validate :org_limit_for_roles, on: :create
  scope :custom_roles_for_org, ->(org) { where(owner_type: "Organization", owner_id: org&.id) }

  def self.sti_name
    "Repository"
  end

  def self.default_event_prefix
    :role
  end

  def self.custom_role_by_name(name, org:)
    return unless org.organization?
    custom_roles_for_org(org).find_by(name: name)
  end

  # Public: is the first role greater than the other?
  #
  # Returns a Boolean
  def self.target_greater_than_or_equal_to_other_role?(target:, other_role:)
    Ability::ACTION_RANKING.fetch(target&.to_sym, 0) >= Ability::ACTION_RANKING.fetch(other_role, 0)
  end

  # Get ids of custom roles whose base roles have a lower rank than param action.
  #
  # action - one of the primary system roles
  #
  # Returns array of custom role ids
  def self.lower_custom_role_ids(action:, org:)
    lower_custom_roles(action: action, org: org).pluck(:id)
  end

  # Get the custom roles whose base roles have a lower rank than param action.
  #
  # action       - a PRIMARY_REPO_BASE_ROLES
  # organization - the target Organization
  #
  # Returns array of custom role ids
  def self.lower_custom_roles(action:, org:)
    return Role.none if action == "none" || action.nil?

    default_action_ranking = Ability::ACTION_RANKING.fetch(action.to_sym, 0)
    lower_roles = Ability::ACTION_RANKING.select { |_role, ranking| ranking < default_action_ranking }.keys

    lower_role_ids = Role.presets.where(name: lower_roles).pluck(:id)
    Role.where(owner_id: org.id, owner_type: "Organization", base_role_id: lower_role_ids)
  end

  # Public: The number of custom roles a given organization can create.
  #
  # - org: the Organization object.
  #
  # Returns an Integer.
  def self.custom_role_limit_for_org(org)
    # GHES don't have business_plus plans
    return ENTERPRISE_CUSTOM_REPO_ROLE_LIMIT if !GitHub.billing_enabled?

    case org.plan
    when GitHub::Plan.business_plus
      BUSINESS_PLUS_CUSTOM_REPO_ROLE_LIMIT
    else
      0
    end
  end

  # Public: Checks if the given action is a system role or a custom repository role and fetches it.
  # This method currently doesn't support internal roles.
  # To fetch internal roles by name, use Role.internal_by_name
  # It will clean up push/pull to write/read
  #
  # perm: string, name of the permission or role
  # org: object, needs to be an organization
  # retrieve_base_role: boolean, if true, returns the base role of a custom role or nil
  #
  # Returns: Role or Nil
  def self.by_name(perm:, org:, retrieve_base_role: false)
    return nil if perm.nil?
    action = clean_push_pull(perm)

    if Role.valid_system_role?(action)
      return Platform::Loaders::Permissions::PresetRole.load(name: action).sync unless retrieve_base_role
    elsif valid_custom_role?(action, org: org) && role = RepositoryRole.custom_role_by_name(action, org: org)
      if retrieve_base_role
        return role.base_role
      else
        return role
      end
    end

    nil
  end

  # Public: Returns the highest-ranking role from a list of roles.
  # Custom roles are higher than system roles of the same base role.
  # Ties are broken by highest role_id.
  #
  # roles: an enumerable of Role
  #
  # Returns Role or Nil
  def self.highest_role(roles)
    return nil if roles.nil? || roles.empty?

    highest = roles.first
    roles.each do |role|
      highest_name  = highest.custom? ? highest.base_role.name : highest.name
      if role.target_greater_than_other_role?(other_role: highest_name)
        highest = role
      elsif role.target_greater_than_or_equal_to_other_role?(other_role: highest_name)
        if role.custom? && !highest.custom?
          highest = role
        elsif (role.custom? == highest.custom?) && role.id > highest.id
          highest = role
        end
      end
    end
    highest
  end

  # Public: Is this role a custom role?
  #
  # Returns a Boolean.
  def custom?
    !preset? && base_role_id.present?
  end

  # Public: Returns the action rank for this role.
  # Action rank is only available for Custom Roles with a base role or for read/triage/write/maintain/admin
  #
  # Returns a Float or false.
  def action_rank
    Ability::ACTION_RANKING[name.to_sym] || Ability::ACTION_RANKING[Role.base_role_ids_to_name[base_role_id]&.to_sym]
  end

  # Public: Returns the name of the base role for a custom Role or the name of system role
  # Returns a String or nil
  def action_name
    custom? ? Role.base_role_ids_to_name[base_role_id] : name
  end

  # Public: is the first role greater than or equal to the other?
  #
  # Returns a Boolean
  def target_greater_than_or_equal_to_other_role?(other_role:)
    target = action_name
    Ability::ACTION_RANKING.fetch(target&.to_sym, 0) >= Ability::ACTION_RANKING.fetch(other_role&.to_sym, 0)
  end

  # Public: is the first role greater than the other?
  #
  # Returns a Boolean
  def target_greater_than_other_role?(other_role:)
    target = custom? ? base_role&.name : self.name
    Ability::ACTION_RANKING.fetch(target&.to_sym, 0) > Ability::ACTION_RANKING.fetch(other_role&.to_sym, 0)
  end

  def less_than_org_default_role?(org)
    raise Role::Error.new("this method doesn't support internal roles") if internal?
    target_ability = custom? ? base_role&.name : self.name
    default_perm = org.default_repository_permission
    Ability::ACTION_RANKING[target_ability.to_sym] < Ability::ACTION_RANKING.fetch(default_perm, 0)
  end

  def greater_or_equal_to_org_default_role?(org)
    !less_than_org_default_role?(org)
  end

  def org_limit_for_roles
    return if preset?
    return unless owner

    custom_role_count = RepositoryRole.custom_roles_for_org(owner).count
    custom_role_limit = RepositoryRole.custom_role_limit_for_org(owner)

    if owner.custom_roles_supported? && custom_role_count >= custom_role_limit
      errors.add(:owner, "is already at the maximum number of custom roles")
    end
  end

  # Internal: Clean push/pull to write/read permissions.
  #
  # - action: string or symbol of an action to be cleaned from push/pull
  #
  # Returns a string
  private_class_method def self.clean_push_pull(action)
    action = action&.to_s

    if action == "push"
      action = "write"
    elsif action == "pull"
      action = "read"
    end
    action
  end
end
