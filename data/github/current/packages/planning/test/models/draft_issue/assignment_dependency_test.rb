# typed: true
# frozen_string_literal: true

require "test_helper"

class DraftIssueAssignmentTest < GitHub::TestCase
  include MemexHelpers

  fixtures do
    @org_admin = create(:verified_user, login: "org-admin")
    @organization = create(:organization, admin: @org_admin)
    @memex_project = create(:memex_project, owner: @organization)
    @memex_project_item = create(:memex_project_item, memex_project: @memex_project)
  end

  context "#assigned_to?" do
    test "returns true if the user is assigned to the draft_issue" do
      draft_issue = create(:draft_issue)
      user = create(:user)
      draft_issue.assignees << user
      assert draft_issue.assigned_to?(user)
    end

    test "returns false if the user is not assigned to the draft_issue" do
      draft_issue = create(:draft_issue)
      user = create(:user)
      refute draft_issue.assigned_to?(user)
    end
  end

  context "#assignees=" do
    test "assigns the given users without altering other attributes" do
      draft_issue = create(:draft_issue)
      user = create(:user)

      assert_no_changes ["draft_issue.title", "draft_issue.body", "draft_issue.memex_project_item_id"] do
        draft_issue.assignees = [user]
      end
      assert_equal [user], draft_issue.assignees
    end
  end

  context "#sorted_assignees_list" do
    context "when the memex project is owned by an organization" do
      test "returns all org members" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)
        admin = @organization.members.first
        member = create(:user)
        @organization.add_member(member)
        suggested_assignees = draft_issue.sorted_assignees_list(current_user: member)

        assert_equal([member, admin], suggested_assignees)
      end

      test "also returns collaborators of the project" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)

        member = create(:user, login: "member")
        @organization.add_member(member)

        repo = create(:repository, organization: @organization)
        collaborator = create(:collaborator, login: "collaborator", repository: repo, action: :write)
        @memex_project.grant_role(collaborator, Role.project_writer_role)

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: member)

        assert_equal(%w[member collaborator org-admin], suggested_assignees.map(&:display_login))
      end

      test "does not return duplicate users" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)

        member = create(:user, login: "member")
        @organization.add_member(member)

        repo = create(:repository, organization: @organization)
        collaborator = create(:collaborator, login: "collaborator", repository: repo, action: :write)

        @memex_project.grant_role(@organization.members.first, Role.project_admin_role) # duplicated
        @memex_project.grant_role(collaborator, Role.project_writer_role)
        @memex_project.grant_role(member, Role.project_writer_role)

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: member)

        assert_equal(%w[member collaborator org-admin], suggested_assignees.map(&:display_login))
      end

      test "returns only public members for a viewer who's not a member of the organization" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)
        public_member = create(:user)
        viewer = create(:user)
        @organization.add_member(public_member)
        @organization.publicize_member(public_member)
        assert_equal([public_member], draft_issue.sorted_assignees_list(current_user: viewer))
      end

      test "current assignees are at the top of the list (after current_user)" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)
        admin = @organization.members.first
        member = create(:user, login: "member") # make sure it's listed before the admin user
        viewer = create(:user)
        assignee = create(:user)
        @organization.add_member(member)
        @organization.add_member(viewer)
        @organization.add_member(assignee)
        draft_issue.assignees << assignee

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: viewer)

        assert_equal([viewer, assignee, member, admin], suggested_assignees)
      end

      test "returns a different list for the same draft issue but different user" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)
        admin = @organization.members.first
        member = create(:user)
        @organization.add_member(member)

        suggestions_for_admin = draft_issue.sorted_assignees_list(current_user: admin)
        suggestions_for_member = draft_issue.sorted_assignees_list(current_user: member)

        refute_equal(suggestions_for_admin.map(&:id), suggestions_for_member.map(&:id))
        assert_equal([admin.id, member.id], suggestions_for_admin.map(&:id))
        assert_equal([member.id, admin.id], suggestions_for_member.map(&:id))
      end

      test "does not return teams" do
        draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)

        admin = @organization.members.first

        team = create(:team, organization: @organization, name: "team")
        @memex_project.grant_role(team, Role.project_writer_role)

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: admin)
        assert_equal(["org-admin"], suggested_assignees.map(&:display_login))
      end
    end

    context "when the memex project is user owned" do
      test "returns all collaborators" do
        owner = create(:user, login: "owner")
        user_memex = create(:memex_project, owner: owner)
        project_item = create(:memex_project_item, memex_project: user_memex)

        member = create(:user, login: "member")
        viewer = create(:user)
        user_memex.grant_role(member, Role.project_reader_role)
        user_memex.grant_role(viewer, Role.project_reader_role)

        draft_issue = create(:draft_issue, memex_project_item: project_item)

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: viewer)

        assert_equal([viewer, member, owner], suggested_assignees)
      end

      test "does not return duplicate users" do
        owner = create(:user, login: "owner")
        user_memex = create(:memex_project, owner: owner)
        project_item = create(:memex_project_item, memex_project: user_memex)

        member = create(:user, login: "member")
        viewer = create(:user, login: "viewer")
        user_memex.grant_role(owner, Role.project_admin_role) # duplicated
        user_memex.grant_role(member, Role.project_reader_role)
        user_memex.grant_role(viewer, Role.project_reader_role)

        draft_issue = create(:draft_issue, memex_project_item: project_item)

        suggested_assignees = draft_issue.sorted_assignees_list(current_user: viewer)

        assert_equal(%w[viewer member owner], suggested_assignees.map(&:display_login))
      end
    end
  end

  context "#filtered_assignees_list" do
    test "returns possible assignees whose profile names match the given query" do
      admin = @organization.members.first
      admin.update(profile_name: "cool name")
      member = create(:user)
      member.update(profile_name: "warm member")
      another_member = create(:user)
      another_member.update(profile_name: "cool member")
      @organization.add_member(member)
      @organization.add_member(another_member)

      draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)

      assert_equal [admin], draft_issue.filtered_assignees_list(admin, "name")
      assert_same_elements [admin, another_member], draft_issue.filtered_assignees_list(admin, "cool")
      assert_same_elements [member, another_member], draft_issue.filtered_assignees_list(admin, "member")
    end

    test "returns possible assignees whose logins match the given query" do
      admin = @organization.members.first
      member = create(:user, login: "cool-login")
      another_member = create(:user, login: "something-else")
      @organization.add_member(member)
      @organization.add_member(another_member)

      draft_issue = create(:draft_issue, memex_project_item: @memex_project_item)

      assert_equal [member], draft_issue.filtered_assignees_list(admin, "cool")
    end
  end
end
