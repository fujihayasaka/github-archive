# typed: true
# frozen_string_literal: true

class EnterpriseFgpMetadata
  attr_reader :label, :category, :description

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
    perms = role.permissions.map(&:action)

    CATEGORIES.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(category, permissions), result|
      permissions.each do |category_permission|
        if perms.include?(category_permission.to_s)
          result[title_for(category)] << description_for(category_permission)
        end
      end
    end
  end

  def self.categories
    CATEGORIES.keys
  end

  def self.category_for(fgp)
    CATEGORIES.each do |category, fgps|
      return category if fgps.include?(fgp)
    end

    :unknown
  end

  def self.description_for(fgp)
    DESCRIPTIONS[fgp] || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    case category
    when :general
      "General"
    when :security
      "Security"
    end
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    case category
    when :general
      "gear"
    when :security
      "shield"
    end
  end

  DESCRIPTIONS = {}

  CATEGORIES = {
    general: %i[],
    security: %i[],
  }
end
