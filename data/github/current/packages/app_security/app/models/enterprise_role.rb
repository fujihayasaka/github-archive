# typed: true
# frozen_string_literal: true

class EnterpriseRole < Role
  BUSINESS_PLUS_CUSTOM_ENT_ROLE_LIMIT = 10
  ENTERPRISE_CUSTOM_ENT_ROLE_LIMIT = 10
  FILTER_FIELDS = [:role, :is]

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
    return ENTERPRISE_CUSTOM_ENT_ROLE_LIMIT if !GitHub.billing_enabled?

    case business.plan
    when GitHub::Plan.business_plus
      BUSINESS_PLUS_CUSTOM_ENT_ROLE_LIMIT
    else
      0
    end
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

  sig { returns(String) }
  def octicon
    "note"
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
end
