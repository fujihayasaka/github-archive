# typed: true
# frozen_string_literal: true

# An Business::Role is a representation of the membership abilities of a user
# within an enterprise (Business).
#
class Business::Role
  attr_reader :business, :member, :organization_count, :installation_count, :collab_repo_count

  class << self
    include ActionView::Helpers::TextHelper
  end

  def initialize(business, member, organization_count: 0, installation_count: 0, collab_repo_count: 0)
    @business           = business
    @member             = member
    @organization_count = organization_count
    @installation_count = installation_count
    @collab_repo_count  = collab_repo_count
  end

  # Public: Get the human-readable name of a role, given the symbol
  # representing the role type.
  #
  # type: A symbol representing the organization role type. Valid roles:
  #       :owner
  #       :billing_manager
  #       :member
  #       :guest_collaborator
  #       :outside_collaborator
  #       :server_member
  #
  # Returns a String that represents the name of the role type, or
  # "Unaffilliated" if type is invalid.
  def self.name_for_type(type)
    case type
    when :owner
      "Enterprise account owner"
    when :billing_manager
      "Billing manager"
    when :member
      "Organization member"
    when :guest_collaborator
      "Guest collaborator"
    when :outside_collaborator
      "Outside collaborator"
    when :server_member
      "Enterprise Server member"
    else
      "Unaffiliated"
    end
  end

  # Public: What does each role mean?
  #
  # Returns a string.
  def self.description_for_type(type, role)
    case type
    when :owner
      "Owners have full administrative rights to the enterprise account."
    when :billing_manager
      "Billing managers can view and manage billing for the enterprise account."
    when :member
      "This person is a member of #{pluralize(role.organization_count, "organization")} within the enterprise account."
    when :guest_collaborator
      "Guest collaborators only have access to internal repositories within organizations where they are a member."
    when :outside_collaborator
      "This person has access to #{pluralize(role.collab_repo_count, "repository")} in enterprise organizations that they are not a member of."
    when :server_member
      "This person is a member of #{pluralize(role.installation_count, "server installation")} within the enterprise account."
    else
      "This person isn’t affiliated with the enterprise account."
    end
  end

  # Public: Get all the types of roles of the specified user in this business.
  #
  # Returns an array OR nil if the business doesn't exist.
  # ex. [:admin]
  # ex. [:direct_member, :billing_manager]
  # ex. [:unaffiliated]
  def types
    @types ||= begin
      return nil if business.nil?

      types = []
      unless member.nil?
        types << :owner if business.owner?(member)
        types << :billing_manager if business.billing_manager?(member)
        types << :member if organization_count > 0
        types << :guest_collaborator if business.enterprise_managed_user_enabled? && member.guest_collaborator?
      end
      types << :server_member if installation_count > 0
      unless member.nil?
        types << :outside_collaborator if collab_repo_count > 0
      end

      types.present? ? types : [:unaffiliated]
    end
  end
end
