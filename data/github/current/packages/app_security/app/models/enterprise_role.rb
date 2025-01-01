# typed: true
# frozen_string_literal: true

class EnterpriseRole < Role
  BUSINESS_PLUS_CUSTOM_ENT_ROLE_LIMIT = 20
  ENTERPRISE_CUSTOM_ENT_ROLE_LIMIT = 20
  FILTER_FIELDS = [:role, :is]

  # If you are changing or adding new octicons, please ensure they are included in the mapping in the React UI for role assignments
  # ui/packages/role-assignments/utils/RoleIconMap.tsx

  SYSTEM_ROLE_METADATA = T.let({
    enterprise_security_manager: {
      display_name: "Enterprise Security Manager",
      description: "Grants the ability to manage security policies, security alerts, and security configurations for an enterprise and all its organizations.",
      octicon: "shield-lock",
      delegate: "security_manager",
    },
    enterprise_app_manager: {
      display_name: "Enterprise App Manager",
      description: "Grants the ability to manage enterprise-owned integrations.",
      octicon: "apps",
    }
  }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

  PRESET_ROLE_NAMES = EnterpriseRole::SYSTEM_ROLE_METADATA.keys.map(&:to_s)

  validate :enterprise_limit_for_roles, on: :create
  scope :custom_roles_for_enterprise, ->(business) { where(owner_type: "Business", owner_id: business&.id) }

  sig { returns(String) }
  def self.sti_name
    "Business"
  end

  def self.custom_role_by_name(name, owner:)
    return unless owner.business?
    custom_roles_for_enterprise(owner).find_by(name: name)
  end

  # Public: The number of custom roles a given business can create.
  #
  # - business: the Business object.
  #
  # Returns an Integer.
  sig { params(business: Business).returns(Integer) }
  def self.custom_role_limit_for_enterprise(business)
    return 0 unless business.custom_enterprise_roles_supported?

    # GHES doesn't have business_plus plans
    return enterprise_custom_ent_role_limit if !GitHub.billing_enabled?

    case business.plan
    when GitHub::Plan.business_plus
      business_plus_custom_ent_role_limit
    else
      0
    end
  end

  # Public: Get the business plus custom enterprise role limit
  #
  # Returns an Integer.
  sig { returns(Integer) }
  def self.business_plus_custom_ent_role_limit
    BUSINESS_PLUS_CUSTOM_ENT_ROLE_LIMIT
  end

  # Public: Get the enterprise custom enterprise role limit
  #
  # Returns an Integer.
  sig { returns(Integer) }
  def self.enterprise_custom_ent_role_limit
    ENTERPRISE_CUSTOM_ENT_ROLE_LIMIT
  end

  # Public: The allowed target types for permissions assignments.
  #
  # Returns an array of strings.
  sig { returns(T::Array[T.untyped]) }
  def allowed_permissions_types
    [target_type]
  end

  # Public: Returns the action rank for this role.
  # Enterprise Roles currently don't have an Action Rank this will always return nil for now
  #
  # Returns a Float or nil.
  sig { returns(Integer) }
  def action_rank
    Ability::ACTION_RANKING[name.to_sym]
  end

  # Public: Returns if the role has a base role
  #
  # Returns a Bool
  sig { returns(T::Boolean) }
  def has_base_role?
    false
  end

  # Public: Returns the octicon for the role
  # If no octicon is defined, the default "note" octicon is returned.
  sig { returns(String) }
  def octicon
    SYSTEM_ROLE_METADATA.dig(name.to_sym, :octicon) || "note"
  end

  # Public: Returns the name of the role formatted for display to users.
  # For custom roles, no change to the role name is made.
  # The names of system and internal roles are titleized unless a custom name is defined in SYSTEM_ROLE_METADATA.
  sig { returns(String) }
  def display_name
    return name if custom?

    SYSTEM_ROLE_METADATA.dig(name.to_sym, :display_name) || name.titleize
  end

  def description
    return super if custom?

    SYSTEM_ROLE_METADATA.dig(name.to_sym, :description) || super
  end

  batch_method(:delegate_organization_role, T.nilable(OrganizationRole)) do |enterprise_roles|
    delegate_names = enterprise_roles.map(&:delegate_organization_role_name).compact.uniq
    delegate_roles_by_name = OrganizationRole.presets.where(name: delegate_names).index_by(&:name)

    enterprise_roles.index_with do |enterprise_role|
      delegate_name = enterprise_role.delegate_organization_role_name
      delegate_name && delegate_roles_by_name[delegate_name]
    end
  end

  sig { returns(T.nilable(String)) }
  def delegate_organization_role_name
    return nil if custom?

    SYSTEM_ROLE_METADATA.dig(name.to_sym, :delegate)
  end

  sig { params(business: Business).returns(T::Array[EnterpriseRole]) }
  def self.visible_roles(business)
    visible_roles = self.visible_preset_roles(business).sort_by(&:name)
    visible_roles += self.custom_roles_for_enterprise(business).sort_by(&:name)

    visible_roles
  end

  def self.matching_roles?(enterprise, enterprise_role_ids, user)
    query = UserRole.where(
     role_id: enterprise_role_ids,
     target_type: "Business",
     target_id: enterprise.id
   )

    if enterprise.erp_feature_enabled?(:custom_enterprise_role_feature) &&
      enterprise.enterprise_rulesets_enterprise_teams_enabled?
      matches = query
        .where(actor_type: "BusinessTeam", actor_id: user.teams(with_business_teams: true).pluck(:id)) # Enterprise role assigned to business team user is member of
        .or(query.where(actor_type: "User", actor_id: user.id))  # Enterprise role assigned to user directly
    else
      # Only check direct role assignments to the user if enterprise roles are not enabled
      matches = query.where(actor_type: "User", actor_id: user.id)
    end
    matches
  end

  sig { params(business: Business).returns(T::Array[EnterpriseRole]) }
  def self.visible_preset_roles(business)
    role_names = []

    if Apps::ManagementHelper.enterprise_app_manager_enabled?(on: business)
      role_names << ENTERPRISE_APP_MANAGER_ROLE
    end

    if business.erp_feature_enabled?(:enterprise_teams_esm)
      role_names << ENTERPRISE_SECURITY_MANAGER_ROLE
    end

    presets.where(name: role_names).to_a
  end

  sig { params(owner: Business).returns(T::Boolean) }
  def visible_for_owner?(owner)
    return owner_id == owner.id if custom?
    return owner.erp_feature_enabled?(:enterprise_teams_esm) if enterprise_security_manager?
    return Apps::ManagementHelper.enterprise_app_manager_enabled?(on: owner) if enterprise_app_manager?

    true
  end

  private

  def valid_base_role
    return unless has_base_role?
    false
  end

  def enterprise_limit_for_roles
    return if preset?
    return unless owner

    custom_role_limit = EnterpriseRole.custom_role_limit_for_enterprise(owner)

    if custom_role_limit == 0
      # As long as we don't lift  the limit of 0 for Custom Enterprise Roles, they are disabled for Customers
      errors.add(:owner, "is not allowed to create custom enterprise roles")
      return
    end

    custom_role_count = EnterpriseRole.custom_roles_for_enterprise(owner).count
    if custom_role_count >= custom_role_limit
      errors.add(:owner, "is already at the maximum number of custom roles")
    end
  end

  def permissions_descriptions(fgps)
    return "None" if fgps.empty?

    descriptions = fgps.map { |fgp| EnterpriseFgpMetadata.description_for(fgp.to_sym) }
    descriptions.to_sentence
  end
end
