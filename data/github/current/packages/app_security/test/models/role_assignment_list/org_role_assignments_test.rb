# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgRoleAssignmentsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @business = create :global_business
    @org = create(:business_plus_organization, login: "github", business: @business)
    @parent_team = create :public_team, organization: @org, name: "Parent Team"
    @child_team = create :public_team, organization: @org, parent_team_id: @parent_team.id, name: "Child Team"
    @grandchild_team = create :public_team, organization: @org, parent_team_id: @child_team.id, name: "Grandchild Team"

    @direct_assigned_user = create :user
    @org.add_member @direct_assigned_user

    @all_team_member = create :user
    @org.add_member @all_team_member

    @parent_team_member = create :user
    @org.add_member @parent_team_member
    @parent_team.add_member @parent_team_member
    @parent_team.add_member @all_team_member

    @child_team_member = create :user
    @org.add_member @child_team_member
    @child_team.add_member @all_team_member
    @child_team.add_member @child_team_member

    @grandchild_team_member = create :user
    @org.add_member @grandchild_team_member
    @grandchild_team.add_member @all_team_member
    @grandchild_team.add_member @grandchild_team_member

    @enterprise_team = create(:enterprise_team, business: @business)
    @et_org_team = create(:team, organization: @org)
    EnterpriseTeamOrganizationMapping.create(enterprise_team: @enterprise_team, organization: @org, team: @et_org_team)

    @role = OrganizationRole.all_repo_write_role
  end

  context "user assignments" do
    test "includes directly assigned user" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User")

      assert_equal 1, assignment_list.assignments.count
      assignment = assignment_list.assignments.first
      assert assignment
      assert_equal @direct_assigned_user, assignment&.actor
      assert_equal @role, assignment&.role
      assert_predicate assignment, :direct?
      refute_predicate assignment, :enterprise_managed?

      assert_same_elements [@direct_assigned_user], assignment_list.assignees
    end

    test "includes users who are indirectly assigned via teams" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: false)

      assignments = assignment_list.assignments
      refute_empty assignments
      assert_equal 2, assignments.count
      assert_same_elements [@grandchild_team_member, @all_team_member], assignments.map(&:actor)
      assert_same_elements [@role, @role], assignments.map(&:role)
      assert_same_elements [false, false], assignments.map(&:direct?)
      assert_equal 0, assignments.count(&:enterprise_managed?)

      # assignees
      expected_assignees = [@all_team_member, @grandchild_team_member].map(&:display_login).sort
      assert_equal expected_assignees, T.cast(assignment_list.assignees, T::Array[User]).map(&:display_login)
    end

    test "teams with some empty team memberships do not impact results" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      empty_team = create :public_team, organization: @org
      @org.grant_org_role(assignee: empty_team, role: @role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: false)

      assignments = assignment_list.assignments
      assert_equal 0, assignments.count(&:enterprise_managed?)

      expected_assignees = [@all_team_member, @grandchild_team_member].map(&:display_login).sort
      assert_equal expected_assignees, T.cast(assignment_list.assignees, T::Array[User]).map(&:display_login)
    end

    test "includes users who are indirectly assigned through child team inheritance" do
      @org.grant_org_role(assignee: @parent_team, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: false)

      assert_same_elements [@all_team_member, @parent_team_member, @child_team_member, @grandchild_team_member], assignment_list.assignees
      assignments = assignment_list.assignments
      assert_equal 0, assignments.count(&:enterprise_managed?)

      # parent team member is assigned to a role through the assigned parent_team via membership in parent_team
      parent_team_member_assignments = assignments.select { |a| a.actor.id == @parent_team_member.id }
      assert_equal 1, parent_team_member_assignments.count
      assignment = parent_team_member_assignments.first

      assert_equal @role.id, assignment&.role&.id
      assert_equal @parent_team.id, assignment&.assigned_team&.id
      assert_equal @parent_team.id, assignment&.through&.id
      assert_predicate assignment, :indirect?

      # child_team member is assigned to a role through the assigned parent_team via membership in child_team
      child_team_member_assignments = assignments.select { |a| a.actor.id == @child_team_member.id }
      assert_equal 1, child_team_member_assignments.count
      assignment = child_team_member_assignments.first

      assert_equal @role.id, assignment&.role&.id
      assert_equal @parent_team.id, assignment&.assigned_team&.id
      assert_equal @child_team.id, assignment&.through&.id
      assert_predicate assignment, :indirect?

      # grandchild_team member is assigned to a role through the assigned parent_team via membership in grandchild_team
      grandchild_team_member_assignments = assignments.select { |a| a.actor.id == @grandchild_team_member.id }
      assert_equal 1, grandchild_team_member_assignments.count
      assignment = grandchild_team_member_assignments.first

      assert_equal @role.id, assignment&.role&.id
      assert_equal @parent_team.id, assignment&.assigned_team&.id
      assert_equal @grandchild_team.id, assignment&.through&.id
      assert_predicate assignment, :indirect?

      # all_team_member is assigned to a role through the assigned parent_team via membership in all teams
      all_team_member_assignments = assignments.select { |a| a.actor.id == @all_team_member.id }
      assert_equal 3, all_team_member_assignments.count
      assert_equal [@parent_team], all_team_member_assignments.map(&:assigned_team).uniq
      assert_same_elements [@parent_team.id, @child_team.id, @grandchild_team.id], all_team_member_assignments.map(&:through).compact.map(&:id)

      # assignees
      expected_assignees = [@all_team_member, @parent_team_member, @child_team_member, @grandchild_team_member].map(&:display_login).sort
      assert_equal expected_assignees, T.cast(assignment_list.assignees, T::Array[User]).map(&:display_login)
    end

    context "security manager role assignments" do
      test "included and not marked as enterprised managed" do
        @org.grant_org_role(assignee: @direct_assigned_user, role: Role.security_manager_role)
        assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: true)

        assignments = assignment_list.assignments
        assert_equal 1, assignments.count
        assignment = T.must(assignments.first)

        assert_predicate assignment, :direct?
        assert_equal @direct_assigned_user, assignment.actor
        assert_equal Role.security_manager_role, assignment.role
        assert_nil assignment.assigned_team
        assert_nil assignment.through
        refute_predicate assignment, :enterprise_managed?
      end
    end
  end

  context "team assignments" do
    test "includes directly assigned team" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: false)

      assert_equal 1, assignment_list.assignments.count

      assignment = T.must(assignment_list.assignments.first)
      assert_predicate assignment, :direct?
      assert_equal @grandchild_team, assignment.actor
      assert_equal @role, assignment.role
      assert_nil assignment.assigned_team
      assert_nil assignment.through
      refute_predicate assignment, :enterprise_managed?

      assert_equal [@grandchild_team], assignment_list.assignees
    end

    test "includes inherited role grants" do
      @org.grant_org_role(assignee: @parent_team, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: false)
      assignments = assignment_list.assignments

      assert_equal 3, assignments.count
      assert_equal 0, assignments.count(&:enterprise_managed?)

      parent_team_assignment = assignments.select { |a| a.actor.id == @parent_team.id }
      assert_equal 1, parent_team_assignment.count

      assignment = T.must(parent_team_assignment.first)
      assert_equal @role, assignment.role
      assert_predicate assignment, :direct?

      child_team_assignment = assignments.select { |a| a.actor.id == @child_team.id }
      assert_equal 1, child_team_assignment.count

      assignment = T.must(child_team_assignment.first)
      assert_equal @role, assignment.role
      refute_predicate assignment, :direct?
      assert_predicate assignment, :indirect?
      assert_equal @parent_team, assignment.assigned_team

      grandchild_team_assignment = assignments.select { |a| a.actor.id == @grandchild_team.id }
      assert_equal 1, grandchild_team_assignment.count

      assignment = T.must(grandchild_team_assignment.first)
      assert_equal @role, assignment.role
      refute_predicate assignment, :direct?
      assert_predicate assignment, :indirect?
      assert_equal @parent_team, assignment.assigned_team

      # assignees
      expected_assignees = [@parent_team, @child_team, @grandchild_team].map(&:slug).sort
      assert_equal expected_assignees, T.cast(assignment_list.assignees, T::Array[Team]).map(&:slug).sort
    end

    # This tests a bug (feature?) in the team descendant loader where grandchild teams
    # had themselves as descendants
    test "mixed child and grandchild team assignments only have one assignment" do
      @org.grant_org_role(assignee: @child_team, role: @role)
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: false)
      assignments = assignment_list.assignments

      assert_equal 3, assignments.count
      assert_equal 2, assignments.count(&:direct?)
      assert_equal 1, assignments.count(&:indirect?)
    end

    # This tests a race condition where a deleted team can have an orphaned user role record
    test "user role records referring to missing teams are ignored" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      @grandchild_team.delete

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: false)

      assert_empty assignment_list.assignments
    end

    context "security manager role assignments" do
      test "included and not marked as enterprised managed for non-enterprise teams" do
        EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

        ::SecurityProduct::SecurityManagerRole.grant_to_team!(@parent_team)
        ::SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team) # Making ESM just to prove it doesn't matter
        assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: true)

        assignments = assignment_list.assignments
        assert_equal 1, assignments.count
        assignment = T.must(assignments.first)

        assert_predicate assignment, :direct?
        assert_equal @parent_team, assignment.actor
        assert_equal Role.security_manager_role, assignment.role
        assert_nil assignment.assigned_team
        assert_nil assignment.through
        refute_predicate assignment, :enterprise_managed?
      end

      context "for enterprise teams" do
        test "not marked as enterprise managed when the enterprise team is not an enterprise security manager team" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          ::SecurityProduct::SecurityManagerRole.grant_to_team!(@et_org_team)
          assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: true)

          assignments = assignment_list.assignments
          assert_equal 1, assignments.count
          assignment = T.must(assignments.first)

          assert_predicate assignment, :direct?
          assert_equal @et_org_team, assignment.actor
          assert_equal Role.security_manager_role, assignment.role
          assert_nil assignment.assigned_team
          assert_nil assignment.through
          refute_predicate assignment, :enterprise_managed?
        end

        test "marked as enterprise managed when the enterprise team is an enterprise security manager team" do
          EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

          ::SecurityProduct::SecurityManagerRole.grant_to_team!(@et_org_team)
          ::SecurityProduct::EnterpriseSecurityManagerRole.grant!(@enterprise_team)

          assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", direct_only: true)

          assignments = assignment_list.assignments
          assert_equal 1, assignments.count
          assignment = T.must(assignments.first)

          assert_predicate assignment, :direct?
          assert_equal @et_org_team, assignment.actor
          assert_equal Role.security_manager_role, assignment.role
          assert_nil assignment.assigned_team
          assert_nil assignment.through
          assert_predicate assignment, :enterprise_managed?
        end
      end
    end
  end

  context "with role_ids" do
    test "user assignments only includes assignments for the filtered role" do
      @org.grant_org_role(assignee: @parent_team_member, role: @role)
      custom_org_role = create_custom_org_role(role_name: "developer", owner: @org)
      @org.grant_org_role(assignee: @direct_assigned_user, role: custom_org_role)

      # ensure that we are actually filtering something out
      assert_equal 2, RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User").assignments.count

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", role_ids: [custom_org_role.id])

      assert_equal 1, assignment_list.assignments.count
      assignment = assignment_list.assignments.first
      assert assignment
      assert_equal assignment&.actor, @direct_assigned_user
      assert_equal assignment&.role, custom_org_role
      assert_predicate assignment, :direct?
    end

    test "team assignments only includes assignments for the filtered role" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      custom_org_role = create_custom_org_role(role_name: "developer", owner: @org)
      @org.grant_org_role(assignee: @grandchild_team, role: custom_org_role)

      # ensure that we are actually filtering something out
      assert_equal 2, RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team").assignments.count

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", role_ids: [custom_org_role.id])

      assert_equal 1, assignment_list.assignments.count
      assignment = assignment_list.assignments.first
      assert assignment
      assert_equal assignment&.actor, @grandchild_team
      assert_equal assignment&.role, custom_org_role
      assert_predicate assignment, :direct?
    end
  end

  context "assignee_ids" do
    test "user and team counts reflect direct assigned users and teams for user actor" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User")
      assert_equal 1, assignment_list.user_assignee_ids.size
      assert_equal 2, assignment_list.team_assignee_ids.size
    end

    test "user and team counts reflect direct assigned users and teams for team actor" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team")
      assert_equal 1, assignment_list.user_assignee_ids.size
      assert_equal 2, assignment_list.team_assignee_ids.size
    end

    test "user and team counts are filtered by role for user actor" do
      read_role = OrganizationRole.all_repo_read_role
      other_direct_user = create :user
      @org.add_member other_direct_user
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: other_direct_user, role: read_role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: read_role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", role_ids: [@role.id])
      assert_equal 1, assignment_list.user_assignee_ids.size
      assert_equal 1, assignment_list.team_assignee_ids.size
    end

    test "user and team counts are filtered by role for team actor" do
      read_role = OrganizationRole.all_repo_read_role
      other_direct_user = create :user
      @org.add_member other_direct_user
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: other_direct_user, role: read_role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: read_role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "Team", role_ids: [@role.id])
      assert_equal 1, assignment_list.user_assignee_ids.size
      assert_equal 1, assignment_list.team_assignee_ids.size
    end

    test "user_assignee_ids and team_assignee_ids include assignees from indirect assignments" do
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: false)
      assert_same_elements [@child_team_member.id, @all_team_member.id,  @grandchild_team_member.id], assignment_list.user_assignee_ids
      assert_same_elements [@child_team.id, @grandchild_team.id], assignment_list.team_assignee_ids
    end
  end
end
