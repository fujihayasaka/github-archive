# typed: strict
# frozen_string_literal: true

module OrgRoles
  class AssigneeRowComponent < ApplicationComponent
    extend T::Sig

    sig { returns(T.any(User, Team)) }
    attr_reader :assignee

    sig { returns(T::Array[RoleAssignmentList::RoleAssignment]) }
    attr_reader :assignments

    sig { returns(Organization) }
    attr_reader :organization

    sig { returns(T::Boolean) }
    attr_reader :stafftools

    class AssigneeType < T::Enum
      enums do
        User = new
        Team = new
      end
    end

    sig { params(organization: Organization, assignee: T.any(User, Team), assignments: T::Array[RoleAssignmentList::RoleAssignment], stafftools: T::Boolean).void }
    def initialize(organization:, assignee: , assignments:, stafftools:)
      @organization = organization
      @assignee = assignee
      @assignments = assignments
      @stafftools = stafftools
    end

    sig { returns(T::Array[RoleAssignmentList::RoleAssignment]) }
    memoize def direct_assignments
      @assignments.select(&:direct?)
    end

    sig { returns(T::Array[RoleAssignmentList::RoleAssignment]) }
    memoize def indirect_assignments
      @assignments.select(&:indirect?)
    end

    sig { returns(T::Hash[T.nilable(Team), T::Array[RoleAssignmentList::RoleAssignment]]) }
    def indirect_by_team
      indirect_assignments.group_by(&:assigned_team)
    end

    sig { params(team: Team).returns(String) }
    def team_link(team)
      if stafftools
        stafftools_user_team_path(organization, team)
      else
        team_path(team, organization: organization)
      end
    end
  end
end
