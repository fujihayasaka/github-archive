# typed: true
# frozen_string_literal: true

class EnterpriseRoleFgps
  include Scientist

  extend T::Sig
  delegate :title_for, :icon_for, to: :EnterpriseFgpMetadata

  # Public: initialize the FGPs with their correspondent metadata.
  #
  # Returns: an EnterpriseRoleFgps containing available FGPs

  def base_role
    ""
  end

  def implicit_fgps
    []
  end

  def self.for(business:)
    new.tap do |role|
      role.available_fgps(business)
    end
  end

  # Public: the set of FGPs
  # These FGPs can be chosen by the user to form a custom role.
  #
  # Returns: a list of FgpMetadata
  def available_fgps(business)
    return @available_fgps if defined?(@available_fgps)

    remaining_roles = self.class.custom_role_fgps(business)

    fgps = remaining_roles.each_with_object([]) do |fgp, result|
      result << EnterpriseFgpMetadata.for(fgp)
    end

    @available_fgps = fgps.sort_by(&:category)
  end

  # Public: the fine grained permissions for a given role which can be assigned to a custom role.
  #
  # - role: the Role object
  #
  # Returns: an Array of symbols
  def self.custom_role_fgps_for(role)
    fgps = role.custom_role_permissions.pluck(:action).map(&:to_sym)
  end

  # Public: all the fine grained permissions which can be assigned to a custom org role.
  # Returns: an Array of symbols
  sig { params(business: Business).returns(T::Array[Symbol]) }
  def self.custom_role_fgps(business)
    Permissions::FineGrainedPermissionIm.permissions_for_custom_roles(business, target_type: "Business").map { |fgp| fgp.action.to_sym }
  end
end
