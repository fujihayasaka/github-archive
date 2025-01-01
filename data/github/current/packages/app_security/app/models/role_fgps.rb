# typed: false
# frozen_string_literal: true

class RoleFgps
  include Scientist

  attr_reader :base_role

  delegate :title_for, :icon_for, to: :FgpMetadata

  # this is a quick-fix for staff-shipping and will be removed shortly
  UNAVAILABLE_FGPS = [:manage_topics, :remove_label, :remove_assignee]

  # RoleFgps is the DTO that encapsulates all metadata related to a set of FGPs for a given base role.
  # For example: having a base role of :triage will mark FGPs such as :add_label as implicit,
  # while marking FGPs such as :manage_repo_metadata as available to be selected additionally.
  # This class is used in the context of creating and managing custom repo roles.
  #
  # base_role: a Symbol
  def initialize(base_role:)
    @base_role = base_role
  end

  # Public: initialize the FGPs with their correspondent metadata.
  #
  # base_role: String or Symbol used to determine the FGPs which are available to choose
  #            versus those which are already implicit in the base role.
  #
  # Returns: a RoleFgps containing implicit and available FGPs for the base role
  #          or nil if the input base role is not one of (read/triage/write/maintain)
  def self.for(base_role:, org:)
    return unless base_role && system_role_fgps.keys.include?(base_role.to_sym)

    new(base_role: base_role.to_sym).tap do |role|
      role.implicit_fgps
      role.available_fgps(org)
    end
  end

  # Public: the set of FGPs that are implicitly available in the base role.
  #
  # Returns: a list of FgpMetadata
  def implicit_fgps
    return @implicit_fgps if defined?(@implicit_fgps)

    fgps = FgpMetadata::CATEGORIES.each_with_object([]) do |(_category, fgps), result|
      fgps.each do |fgp|
        if self.class.system_role_fgps[@base_role].include?(fgp)
          result << FgpMetadata.for(fgp)
        end
      end
    end

    @implicit_fgps = fgps.sort_by(&:category)
  end

  # Public: the set of FGPs that are not implicit in the base role.
  # These FGPs can be chosen by the user to form a custom repo role.
  #
  # Returns: a list of FgpMetadata
  def available_fgps(org)
    return @available_fgps if defined?(@available_fgps)

    remaining_roles = self.class.custom_role_fgps(org) - implicit_fgps.map(&:label)

    fgps = remaining_roles.each_with_object([]) do |fgp, result|
      result << FgpMetadata.for(fgp)
    end

    @available_fgps = fgps.sort_by(&:category)
  end

  # Public: the fine grained permissions for a given role which can be assigned to a custom repo role.
  #
  # - role: the Role object
  #
  # Returns: an Array of symbols
  def self.custom_role_fgps_for(role)
    fgps = role.custom_role_permissions.pluck(:action).map(&:to_sym)
    fgps.delete_if { |fgp| UNAVAILABLE_FGPS.include?(fgp) }
  end

  # Public: all the fine grained permissions which can be assigned to a custom repo role.
  #
  # Returns: an Array of symbols
  def self.custom_role_fgps(org)
    Permissions::FineGrainedPermissionIm.permissions_for_custom_roles(org, target_type: "Repository").map { |fgp| fgp.action.to_sym }
  end

  # Public: the fine grained permissions which can be assigned to a custom repo role
  # for every valid base role. Admin is not supported as base role
  #
  # Returns: a symbolized Hash of role-name => [fgp name]
  def self.system_role_fgps
    @system_role_fgps ||= {
      read:     custom_role_fgps_for(Role.read_role),
      triage:   custom_role_fgps_for(Role.triage_role),
      write:    custom_role_fgps_for(Role.write_role),
      maintain: custom_role_fgps_for(Role.maintain_role)
    }
  end

  def self.fgps_payload(organization)
    fgp_per_base_role = system_role_fgps
    repo_fgps = self.for(base_role: "read", org: organization).available_fgps(organization)
    label_to_base_role = {}
    fgp_per_base_role.each do |base_role, labels|
      labels.each do |label|
        label_to_base_role[label] = base_role unless label_to_base_role.key?(label)
      end
    end

    response = {}
    repo_fgps.each do |repo_fgp|
      response[repo_fgp.label] = {
        category: repo_fgp.category,
        description: repo_fgp.description,
        label: repo_fgp.label,
        base_role: label_to_base_role[repo_fgp.label],
      }
    end
    response
  end
end
