# typed: true
# frozen_string_literal: true

# Roles a business user account can have in a business.
module BusinessUserAccount::Roles
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig
  requires_ancestor { BusinessUserAccount }

  # Roles a user can have in a business. These are stored as a bitfield in the database.
  # Do not re-use a number. They are stored in the database and re-using them would be a breaking change.
  # You can delete a role and add a new one, and assign the new role the next available number.
  BUSINESS_ROLES = {
    unaffiliated: 0,
    member: 1 << 0,
    owner: 1 << 1,
    emu_admin: 1 << 2,
    billing_manager: 1 << 3,
    guest_collaborator: 1 << 5,
    outside_collaborator: 1 << 6,
    server_member: 1 << 7,
    server_admin: 1 << 8,
    suspended: 1 << 9,
  }

  included do
    T.bind(self, T.class_of(BusinessUserAccount))
    scope :roles, ->(roles) { where("business_roles_bitfield & :bitmask", bitmask: BusinessUserAccount.roles_bitmask(roles)) }
    scope :no_roles, ->(roles) { where("business_roles_bitfield & :bitmask = 0", bitmask: BusinessUserAccount.roles_bitmask(roles)) }
    scope :exclusive_roles, ->(roles) { where("business_roles_bitfield = :bitmask", bitmask: BusinessUserAccount.roles_bitmask(roles)) }
    scope :exclusive_no_roles, ->(roles) { where("business_roles_bitfield != :bitmask", bitmask: BusinessUserAccount.roles_bitmask(roles)) }
    scope :unaffiliated_role, -> { no_roles([:member, :owner, :emu_admin, :billing_manager, :outside_collaborator]) }
    scope :exclusive_unaffiliated_role, -> { where("business_user_accounts.business_roles_bitfield = 0") }
    scope :exclude_unaffiliated_role, -> { where("business_roles_bitfield != 0") }
  end

  module ClassMethods
    def roles_bitmask(roles)
      roles = [roles] unless roles.is_a?(Array)
      roles.sum { |role| BUSINESS_ROLES[role] || 0 }
    end
  end

  # Public: Returns an array of symbols representing the business roles the user has.
  sig { returns(T::Array[Symbol]) }
  def business_roles
    return [] if business_roles_bitfield.nil? # Job has not run to set business roles yet.
    return [BUSINESS_ROLES.key(0)] if business_roles_bitfield == 0

    BUSINESS_ROLES.keys.select { |role| business_roles_bitfield & BUSINESS_ROLES[role] != 0 }
  end

  # Public: Sets the business roles for a user. This will remove any existing roles and replace them with the roles
  # passed in.
  sig { params(roles: T::Array[Symbol]).void }
  def set_business_roles(roles)
    reset_business_roles(save: false)
    add_business_roles(roles)
    self.save!
  end

  # Public: Checks if the user has a specified business role.
  sig { params(role: Symbol).returns(T::Boolean) }
  def has_business_role?(role)
    return business_roles_bitfield == 0 if role == :unaffiliated
    (business_roles_bitfield & BUSINESS_ROLES[role]) != 0
  end

  # Public: Checks if the user has no business roles.
  sig { returns(T::Boolean) }
  def has_no_business_role?
    business_roles_bitfield.to_i == 0
  end

  # Private: Adds business roles to the user.
  sig { params(roles: T::Array[Symbol]).void }
  def add_business_roles(roles)
    roles.each do |role|
      next unless BUSINESS_ROLES.key?(role)
      # This is the same as `self.business_roles_bitfield |= BUSINESS_ROLES[role]` which would not work if
      # business_roles_bitfield is nil.
      self.business_roles_bitfield = self.business_roles_bitfield.to_i | BUSINESS_ROLES[role]
    end
  end

  # Private: Removes business roles from the user.
  sig { params(roles: T::Array[Symbol]).void }
  def remove_business_roles(roles)
    roles.each do |role|
      next unless BUSINESS_ROLES.key?(role)
      # This is the same as `self.business_roles_bitfield &= ~BUSINESS_ROLES[role]` which would not work if the field
      # is nil.
      self.business_roles_bitfield = self.business_roles_bitfield.to_i & ~BUSINESS_ROLES[role]
    end
  end

  private

  # Private: Removes all business roles from the user. This will leave the user with business roles defined as no
  # roles.
  sig { params(save: T::Boolean).void }
  def reset_business_roles(save: true)
    self.business_roles_bitfield = 0
    self.save! if save
  end
end
