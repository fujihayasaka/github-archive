# typed: true
# frozen_string_literal: true

class OrgRoles::FormComponent < ApplicationComponent
  include GitHub::Memoizer

  attr_reader :organization
  attr_reader :base_role_fgps
  attr_reader :role
  attr_reader :assignment_counts

  def initialize(organization:, base_role_fgps:, role: nil, assignment_counts: nil)
    @organization = organization
    @base_role_fgps = base_role_fgps
    @role = role
    @assignment_counts = assignment_counts
  end

  private

  # All the available categories, with their implicit FGPs if any.
  #
  # Returns a Hash of category symbols to FGPMetadata
  memoize def categories
    implicit_cats = implicit_categories
    categories = OrgFgpMetadata.categories.each_with_object({}) do |category, hash|
      hash[category] = implicit_cats[category] || []
    end
    categories
  end

  # Is the given FGP part of the additional FGPs for the custom role.
  #
  # - fgp: the FGP label in string or symbol format.
  #
  # Returns a Boolean
  def is_additional_fgp?(fgp)
    return false unless role

    @permissions = role.permissions.pluck(:action) unless defined?(@permissions)
    @permissions.include?(fgp.to_s)
  end

  # implicit categories only apply if there is a base role.
  def implicit_categories
    {}
  end

  def new_page?
    role.nil?
  end

  def form_url
    new_page? ? settings_org_roles_path(organization) : update_settings_org_roles_path(organization, role)
  end

  def org_fgp_metadata_url
    settings_org_roles_fgp_metadata_path(organization)
  end

  def repo_fgp_metadata_url
    autocomplete_repository_permissions_path(organization)
  end

  def index_url
    settings_org_roles_path(organization)
  end

  def http_method
    new_page? ? :post : :put
  end

  def icon_for(category)
    OrgFgpMetadata.icon_for(category)
  end

  def title_for(category)
    OrgFgpMetadata.title_for(category)
  end

  def role_user_count
    assignment_counts["User"] || 0
  end

  def role_team_count
    assignment_counts["Team"] || 0
  end

  def repo_fgps
    roles_order = [:triage, :write, :maintain, nil]
    RoleFgps.fgps_payload(organization).values.sort_by { |item| roles_order.index(item[:base_role]) }
  end

  def is_active_base_role?(base_role_name)
    return false unless role&.base_role

    base_role_name == role.base_role.name
  end

  memoize def initial_base_role
    role.base_role.name if role && role.base_role
  end

  memoize def initial_edit_role_permissions
    @role.permissions.map(&:action) if @role
  end
end
