# typed: strict
# frozen_string_literal: true

module OrgRoles
  class AssignmentRowComponent < ApplicationComponent
    sig { returns(Organization) }
    attr_reader :organization

    sig { returns(RoleAssignmentList::RoleAssignment) }
    attr_reader :assignment

    sig { returns(T::Boolean) }
    attr_reader :stafftools

    sig { params(organization: Organization, assignment: RoleAssignmentList::RoleAssignment, stafftools: T::Boolean).void }
    def initialize(organization:, assignment:, stafftools:)
      @organization = organization
      @assignment = assignment
      @stafftools = stafftools
    end

    sig { returns(String) }
    def delete_url
      delete_org_role_assignments_url(@organization, assignee.class.to_s.downcase, assignee.id, role.id)
    end

    private

    sig { returns(T.any(User, Team)) }
    def assignee
      assignment.actor
    end

    sig { returns(Role) }
    def role
      assignment.role
    end

    sig { returns(T::Boolean) }
    def display_remove_button?
      assignment.direct? && !stafftools && !assignment.enterprise_managed?
    end

    sig { returns(String) }
    def enterprise_role_assignments_path
      # Today there is only the ESM assignments page,
      # but once there is an enterprise role assignments page, the path will become conditional
      # on whether the current role is the ESM role.
      enterprise_security_managers_path(organization.business)
    end
  end
end
