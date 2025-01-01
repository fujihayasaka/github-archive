# typed: strict
# frozen_string_literal: true

module OrgRoles
  class AssignmentRowComponent < ApplicationComponent
    extend T::Sig
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
      assignment.direct? && !stafftools
    end
  end
end
