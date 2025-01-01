# typed: true
# frozen_string_literal: true

class OrgFgpMetadata
  attr_reader :label, :category, :description

  # Fine Grained Permission metadata
  def initialize(fgp)
    @label = fgp
    @category = OrgFgpMetadata.category_for(fgp)
    @description = OrgFgpMetadata.description_for(fgp)
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

  private_class_method def self.for_permissions(permissions)
    fgps_by_category = Permissions::FineGrainedPermissionIm.where(actions: permissions.map(&:action), target_type: "Organization").group_by(&:category)

    CATEGORY_ORDER.each_with_object({}) do |category, result|
      next unless (fgps = fgps_by_category[category])

      result[title_for(category)] = fgps.map(&:description)
    end
  end

  def self.categories
    CATEGORY_ORDER
  end

  def self.category_for(fgp)
    return :unknown unless (fgp_im = Permissions::FineGrainedPermissionIm.org_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.category || :unknown
  end

  def self.description_for(fgp)
    return "unknown" unless (fgp_im = Permissions::FineGrainedPermissionIm.org_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.description || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    case category
    when :access_management
      "Identity and access management"
    when :automation
      "Apps and automation"
    when :general
      "General"
    when :repository
      "Repository"
    when :security
      "Security"
    when :ci_cd
      "CI/CD"
    end
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    case category
    when :access_management
      "unlock"
    when :automation
      "hubot"
    when :general
      "gear"
    when :repository
      "repo"
    when :security
      "shield"
    when :ci_cd
      "workflow"
    end
  end

  # Public: the octicon for every FGP category by title
  # hard coded for now
  def self.icon_for_title(title)
    case title
    when "Identity and access management"
      "unlock"
    when "Apps and automation"
      "hubot"
    when "General"
      "gear"
    when "Repository"
      "repo"
    when "Security"
      "shield"
    when "CI/CD"
      "workflow"
    end
  end

  CATEGORY_ORDER = %i(general access_management security automation repository ci_cd).freeze
end
