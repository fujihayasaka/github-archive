# typed: true
# frozen_string_literal: true

class OrgRoleFgps
  include Scientist

  delegate :title_for, :icon_for, to: :OrgFgpMetadata

  # Public: initialize the FGPs with their correspondent metadata.
  #
  # Returns: an OrgRoleFgps containing available FGPs

  def base_role
    ""
  end

  def implicit_fgps
    []
  end

  def self.for(owner:)
    new.tap do |role|
      role.available_fgps(owner)
    end
  end

  # Public: the set of FGPs
  # These FGPs can be chosen by the user to form a custom role.
  #
  # Returns: a list of FgpMetadata
  sig { params(owner: T.any(Business, Organization)).returns(T::Array[OrgFgpMetadata]) }
  def available_fgps(owner)
    return @available_fgps if defined?(@available_fgps)

    remaining_roles = self.class.custom_role_fgps(owner)

    fgps = remaining_roles.each_with_object([]) do |fgp, result|
      result << OrgFgpMetadata.for(fgp)
    end

    @available_fgps = fgps.sort_by(&:category)
  end

  # Public: the fine grained permissions for a given role which can be assigned to a custom role.
  #
  # - role: the Role object
  #
  # Returns: an Array of symbols
  sig { params(role: OrganizationRole).returns(T::Array[Symbol]) }
  def self.custom_role_fgps_for(role)
    fgps = role.custom_role_permissions.pluck(:action).map(&:to_sym)
  end

  sig { params(business: Business).returns(T::Array[Symbol]) }
  def self.custom_role_fgps_for_business(business)
    Permissions::FineGrainedPermissionIm.permissions_for_custom_roles(business, target_type: "Organization").map { |fgp| fgp.action.to_sym }
  end

  # Public: all the fine grained permissions which can be assigned to a custom org role.
  # Returns: an Array of symbols
  sig { params(owner: T.any(Business, Organization)).returns(T::Array[Symbol]) }
  def self.custom_role_fgps(owner)
    Permissions::FineGrainedPermissionIm.permissions_for_custom_roles(owner, target_type: "Organization").map { |fgp| fgp.action.to_sym }
  end

  # Public: the fine grained permissions which can be assigned to a custom role formatted for React frontend.
  #
  # Returns: an Array of Hashes with label, description and category
  sig { params(owner: T.any(Business, Organization)).returns(T::Array[T::Hash[Symbol, String]]) }
  def self.fgps_payload_for_react(owner)
    fgps = custom_role_fgps(owner).map do |fgp|
      fgp_metadata = OrgFgpMetadata.for(fgp)

      {
        label: fgp_metadata.label,
        description: fgp_metadata.description,
        category: OrgFgpMetadata.title_for(fgp_metadata.category),
      }
    end

    fgps.sort_by { |fgp| fgp[:category] }
  end
end
