# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgRoleAssigneesTest < GitHub::TestCase
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

  context "user assignees" do
    test "includes directly assigned user" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org)
      user_ids = assignees.user_assignee_ids

      assert_equal 1, user_ids.count
      assert_same_elements [@direct_assigned_user], User.where(id: user_ids)
    end

    test "includes users who are indirectly assigned via teams" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, direct_only: false)
      user_ids = assignees.user_assignee_ids

      assert_equal 2, user_ids.count
      assert_same_elements [@grandchild_team_member, @all_team_member], User.where(id: user_ids)
    end

    test "teams with some empty team memberships do not impact results" do
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      empty_team = create :public_team, organization: @org
      @org.grant_org_role(assignee: empty_team, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, direct_only: false)
      user_ids = assignees.user_assignee_ids

      assert_equal 2, user_ids.count
      assert_same_elements [@all_team_member, @grandchild_team_member], User.where(id: user_ids)
    end

    test "includes users who are indirectly assigned through child team inheritance" do
      @org.grant_org_role(assignee: @parent_team, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, direct_only: false)
      user_ids = assignees.user_assignee_ids

      assert_equal 4, user_ids.count
      assignment_list = RoleAssignmentList::OrgRoleAssignments.new(organization: @org, actor_type: "User", direct_only: false)

      assert_same_elements [@all_team_member, @parent_team_member, @child_team_member, @grandchild_team_member], User.where(id: user_ids)
    end

    context "security manager role assignees" do
      test "included" do
        @org.grant_org_role(assignee: @direct_assigned_user, role: Role.security_manager_role)
        assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, direct_only: true)

        user_ids = assignees.user_assignee_ids
        assert_same_elements [@direct_assigned_user], User.where(id: user_ids)
      end
    end
  end

  context "with role_ids" do
    test "user assignees only includes assinees for the filtered role" do
      @org.grant_org_role(assignee: @parent_team_member, role: @role)
      custom_org_role = create_custom_org_role(role_name: "developer", owner: @org)
      @org.grant_org_role(assignee: @direct_assigned_user, role: custom_org_role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org)
      user_assignees = User.where(id: assignees.user_assignee_ids)

      assert_same_elements [@direct_assigned_user, @parent_team_member], user_assignees

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, role_ids: [custom_org_role.id])
      user_assignees = User.where(id: assignees.user_assignee_ids)

      assert_same_elements [@direct_assigned_user], user_assignees
    end

    test "team assignees only includes assignments for the filtered role" do
      @org.grant_org_role(assignee: @child_team, role: @role)
      @org.grant_org_role(assignee: @grandchild_team, role: @role)
      custom_org_role = create_custom_org_role(role_name: "developer", owner: @org)
      @org.grant_org_role(assignee: @grandchild_team, role: custom_org_role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org)
      team_assignees = Team.where(id: assignees.team_assignee_ids)

      assert_same_elements [@child_team, @grandchild_team], team_assignees

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, role_ids: [custom_org_role.id])
      team_assignees = Team.where(id: assignees.team_assignee_ids)

      assert_same_elements [@grandchild_team], team_assignees
    end
  end

  context "assignee_ids" do
    test "user and team counts reflect direct assigned users and teams for user actor" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org)
      assert_equal 1, assignees.user_assignee_ids.size
      assert_equal 2, assignees.team_assignee_ids.size
    end

    test "user and team counts reflect direct assigned users and teams for team actor" do
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org)
      assert_equal 1, assignees.user_assignee_ids.size
      assert_equal 2, assignees.team_assignee_ids.size
    end

    test "user and team counts are filtered by role for user actor" do
      read_role = OrganizationRole.all_repo_read_role
      other_direct_user = create :user
      @org.add_member other_direct_user
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: other_direct_user, role: read_role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: read_role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, role_ids: [@role.id])
      assert_equal 1, assignees.user_assignee_ids.size
      assert_equal 1, assignees.team_assignee_ids.size
    end

    test "user and team counts are filtered by role for team actor" do
      read_role = OrganizationRole.all_repo_read_role
      other_direct_user = create :user
      @org.add_member other_direct_user
      @org.grant_org_role(assignee: @direct_assigned_user, role: @role)
      @org.grant_org_role(assignee: other_direct_user, role: read_role)
      @org.grant_org_role(assignee: @parent_team, role: @role)
      @org.grant_org_role(assignee: @child_team, role: read_role)

      assignees = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, role_ids: [@role.id])
      assert_equal 1, assignees.user_assignee_ids.size
      assert_equal 1, assignees.team_assignee_ids.size
    end

    test "user_assignee_ids and team_assignee_ids include assignees from indirect assignments" do
      @org.grant_org_role(assignee: @child_team, role: @role)

      assignment_list = RoleAssignmentList::OrgRoleAssignees.new(organization: @org, direct_only: false)
      assert_same_elements [@child_team_member.id, @all_team_member.id,  @grandchild_team_member.id], assignment_list.user_assignee_ids
      assert_same_elements [@child_team.id, @grandchild_team.id], assignment_list.team_assignee_ids
    end
  end
end
