# typed: true
# frozen_string_literal: true

module OrgRoles
  class AssignmentListComponent < ApplicationComponent
    class AssignmentTab < T::Enum
      enums do
        User = new
        Team = new
      end
    end

    class OrgRoleAssignments < T::Struct
      prop :direct, T::Array[Role]
    end

    sig { returns(Organization) }
    attr_reader :organization

    sig { returns(T::Array[T.any(User, Team)]) }
    attr_reader :assignees

    sig { returns(RoleAssignmentList::OrgRoleAssignments) }
    attr_reader :assignment_data

    sig { returns(T.nilable(Integer)) }
    attr_reader :user_count

    sig { returns(T.nilable(Integer)) }
    attr_reader :team_count

    sig { returns(T::Array[Role]) }
    attr_reader :visible_roles

    def initialize(organization:, assignees:, assignment_data:, user_count:, team_count:, query_hash:, active_tab:, visible_roles:, stafftools: false)
      @organization = organization
      @assignees = assignees
      @assignment_data = assignment_data
      @user_count = user_count
      @team_count = team_count
      @query_hash = query_hash
      @visible_roles = visible_roles
      @active_tab = active_tab
      @stafftools = stafftools
    end

    private

    sig { returns(T::Boolean) }
    def user_tab_selected?
      @active_tab == OrgRoles::AssignmentListComponent::AssignmentTab::User
    end

    sig { returns(T::Boolean) }
    def stafftools?
      @stafftools
    end

    sig { returns(String) }
    def index_url
      @stafftools ? stafftools_user_org_role_assignments_path(organization) : settings_org_role_assignments_path(organization)
    end

    sig { returns(T::Boolean) }
    memoize def display_assignment_buttons?
      @stafftools ? false : organization.adminable_by?(current_user)
    end

    sig { params(filter: T::Hash[Symbol, String]).returns(String) }
    def get_query(filter: {})
      OrganizationRole.stringify_query_hash(@query_hash.merge(filter))
    end

    sig { returns(T::Hash[Integer, T::Array[RoleAssignmentList::RoleAssignment]]) }
    memoize def assignments_by_actor_id
      assignment_data.assignments.group_by { |a| T.must(a.actor.id) }
    end

    sig { params(assignee_id: Integer).returns(T::Array[RoleAssignmentList::RoleAssignment]) }
    def assignments_for_assignee(assignee_id)
      T.must(assignments_by_actor_id[assignee_id])
    end
  end
end
