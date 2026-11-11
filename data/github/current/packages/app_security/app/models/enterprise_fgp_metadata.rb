# typed: true
# frozen_string_literal: true

class EnterpriseFgpMetadata
  attr_reader :label, :category, :description

  # Icon needs to be a valid octicon name. Keep `general` at the top and then alphabetical.
  # New categories should be the "blank" when a user thinks "Hm, to fix my problem, I should find my 'blank' admin".
  CATEGORIES = {
    general: { title: "General", icon: "gear" }, # Create/remove organization, update metadata. "Misc"
    access_management: { title: "Identity and access management", icon: "unlock" }, # Invitations, SCIM, team management, role management
    automation: { title: "Apps and automation", icon: "hubot" }, # Manage apps, set token policies
    billing_and_licensing: { title: "Billing and licensing", icon: "credit-card" }, # Create cost centers, manage licenses of all kinds
    ci_cd: { title: "CI/CD", icon: "workflow" },
    copilot: { title: "Copilot", icon: "copilot" },
    repository_settings: { title: "Repositories", icon: "repo" }, # Properties, defaults
    security: { title: "Code Security", icon: "shield" } # Security products like GHAS. Enabling SAML, 2FA, etc is in access management.
  }.freeze

  CATEGORY_ORDER = CATEGORIES.keys.freeze
  TITLES_TO_ICONS = CATEGORIES.map { |_, v| [v[:title], v[:icon]] }.to_h

  # Fine Grained Permission metadata
  def initialize(fgp)
    @label = fgp
    @category = EnterpriseFgpMetadata.category_for(fgp)
    @description = EnterpriseFgpMetadata.description_for(fgp)
  end

  # FGP contains the metadata for an individual fine grained permission
  def self.for(fgp)
    new(fgp.to_sym)
  end

  # Public: get all the categories and FGPs for a role
  #
  # - role: the Role object
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_role(role)
    for_permissions(role.permissions)
  end

  # Public: get all the categories and FGPs for multiple roles
  #
  # - roles: an Array of Role objects
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_roles(roles)
    for_permissions(roles.flat_map(&:permissions))
  end

  # Public: get FGPs for a role, grouped by category title
  #
  # - role: the Role object
  #
  # Returns a Hash of category titles to arrays of FineGrainedPermissionIm objects:
  #   {
  #     "General" => [<FGP>, <FGP>],
  #     "Code Security" => [<FGP>, <FGP>]
  #   }
  #   Sorted by CATEGORY_ORDER
  def self.fgps_for_role(role)
    fgps = fgps_for_permissions(role.permissions)

    CATEGORY_ORDER.each_with_object({}) do |category, result|
      category_fgps = fgps.select { |fgp| fgp.category == category }
      result[title_for(category)] = category_fgps unless category_fgps.empty?
    end
  end

  private_class_method def self.fgps_for_permissions(permissions)
    actions = permissions.map(&:action)
    Permissions::FineGrainedPermissionIm.where(actions: actions, target_type: "Business")
  end

  private_class_method def self.for_permissions(permissions)
    fgps_by_category = fgps_for_permissions(permissions).group_by(&:category)

    CATEGORY_ORDER.each_with_object({}) do |category, result|
      next unless (fgps = fgps_by_category[category])

      result[title_for(category)] = fgps.map(&:description)
    end
  end

  def self.categories
    CATEGORY_ORDER
  end

  def self.category_for(fgp)
    return :unknown unless (fgp_im = Permissions::FineGrainedPermissionIm.enterprise_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.category || :unknown
  end

  def self.description_for(fgp)
    return "unknown" unless (fgp_im = Permissions::FineGrainedPermissionIm.enterprise_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.description || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    CATEGORIES.dig(category, :title)
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    CATEGORIES.dig(category, :icon)
  end

  # Public: the octicon for every FGP category by title. Hard coded for now
  def self.icon_for_title(title)
    TITLES_TO_ICONS[title]
  end
end
