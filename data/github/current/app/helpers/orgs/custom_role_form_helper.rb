# typed: false
# frozen_string_literal: true

module Orgs::CustomRoleFormHelper
  include GitHub::Memoizer
  # Public: all the available categories, with their implicit FGPs if any.
  #
  # Returns a Hash of category symbols to FGPMetadata
  def categories
    return @categories if defined?(@categories)

    implicit_cats = implicit_categories
    @categories = RepoFgpMetadata.categories.each_with_object({}) do |category, hash|
      hash[category] = implicit_cats[category] || []
    end
  end

  # Public: convenience method to check whether to display the FGP summary list at render time
  def has_implicit_fgps?
    implicit_categories.any?
  end

  def fgp_metadata_url
    settings_org_fgp_metadata_path(organization, base_role: "read")
  end

  def form_url
    new_page? ? settings_org_repository_roles_path(organization) : update_settings_org_repository_roles_path(organization, role)
  end

  def http_method
    new_page? ? :post : :put
  end

  def button_text
    new_page? ? "Create role" : "Update role"
  end

  # Public: convenience method to fetch disabled fgps for this org
  memoize def org_disabled_fgps
    Permissions::FineGrainedPermissionIm.disabled_fgps(organization)
  end

  # public: is the given FGP part of the additional FGPs for the custom role.
  #
  # - fgp: the FGP label in string or symbol format.
  #
  # Returns a Boolean
  def is_additional_fgp?(fgp)
    return false unless role

    @permissions = role.permissions.pluck(:action) unless defined?(@permissions)
    @permissions.include?(fgp.to_s)
  end

  # Public: convenience method to decide if we auto-select a given base role input element.
  # For a new custom role, we auto-select 'read'.
  # For editing a custom role, we auto-select the role's base role.
  def is_base_role?(role_type)
    if new_page? || "admin" == role_type
      "read" == role_type
    else
      base_role_fgps.base_role.to_s == role_type
    end
  end

  def new_page?
    role.nil?
  end

  private

  # Internal: the categories for every implicit FGP.
  #
  # Returns a Hash of category symbols to FGPMetadata
  def implicit_categories
    return {} unless base_role_fgps

    base_role_fgps.implicit_fgps.each_with_object({}) do |fgp, hash|
      next if Permissions::FineGrainedPermissionIm.disabled_fgps(organization).include?(fgp)
      hash[fgp.category] = [] unless hash[fgp.category]
      hash[fgp.category] << fgp
    end
  end
end
