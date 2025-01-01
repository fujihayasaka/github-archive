# typed: true
# frozen_string_literal: true

# An Organization::Role is a representation of the membership abilities of a user
# within an organization.
#
class Organization
  class Role
    attr_reader :organization, :member

    def initialize(organization, member)
      @organization = organization
      @member       = member
    end

    # Public: Has the member been suspended by an Identity Provider?
    #
    # Returns Boolean
    def suspended?
      return false if member.nil?
      return false unless member.is_enterprise_managed?
      return false if member.is_first_emu_owner?

      return true if member.external_identities.empty?
      member.external_identities.first&.disabled_at?
    end

    # Public: Get the human-readable name of a role, given the symbol
    # representing the role type.
    #
    # Note that this is used for roles of existing organization membership
    # as well as for roles of pending organization invitations.
    #
    # type: A symbol representing the organization role type. Either :admin,
    #       :direct_member (or just :member), :outside_collaborator,
    #       or :billing_manager.
    #
    # Returns a String that represents the name of the role type, or
    # "Unaffilliated" if type is invalid.
    def self.name_for_type(type)
      case type
      when :admin
        "Owner"
      when :direct_member, :member
        "Member"
      when :outside_collaborator
        "Outside collaborator"
      when :billing_manager
        "Billing manager"
      when :suspended
        "Suspended member"
      when :reinstate
        "Reinstate"
      else
        "Unaffiliated"
      end
    end

    # Public: Get the 'type' of role of the specified user in this org.
    #
    # Returns a symbol or nil if the member or org doesn't exist.
    def type
      @type ||= begin
        return nil if member.nil?
        return nil if organization.nil?

        if suspended?
          :suspended
        elsif organization.adminable_by?(member)
          :admin
        elsif organization.direct_member?(member)
          :direct_member
        elsif organization.user_is_outside_collaborator?(member.id)
          :outside_collaborator
        else
          :unaffiliated
        end
      end
    end

    # Public: Get all the types of roles of the specified user in this org.
    #
    # Returns an array OR nil if the member or org doesn't exist.
    # ex. [:admin]
    # ex. [:direct_member, :billing_manager]
    # ex. [:unaffiliated]
    def types
      @types ||= begin
        return nil if member.nil?
        return nil if organization.nil?

        types = []
        types << :suspended if suspended?
        if organization.direct_member?(member)
          types << (organization.adminable_by?(member) ? :admin : :direct_member)
        end
        types << :outside_collaborator if organization.user_is_outside_collaborator?(member.id)
        types << :billing_manager if organization.billing_manager?(member)

        types.present? ? types : [:unaffiliated]
      end
    end

    # Public: Whether this role can be modified by a given user.
    #
    # actor - The user who would be modifying the role.
    #
    # Returns a boolean.
    def can_be_modified_by?(actor)
      actor != member && modifiable_type? && organization.adminable_by?(actor)
    end

    def admin?
      type == :admin
    end

    def direct_member?
      type == :direct_member
    end

    def outside_collaborator?
      type == :outside_collaborator
    end

    private

    def modifiable_type?
      [:admin, :direct_member].include?(type)
    end
  end
end
