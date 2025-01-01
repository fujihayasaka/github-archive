# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProjectsDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @owner = @org.admins.first
  end

  context ".ids_with_organization_projects_disabled" do
    test "returns a subset of given list, including only those that have disabled org projects" do
      org2 = create(:organization)
      @org.disable_organization_projects(actor: @owner)
      org_ids = [@org.id, org2.id]

      result = Organization.ids_with_organization_projects_disabled(org_ids)

      assert_includes result, @org.id
      refute_includes result, org2.id
    end

    test "returns an empty list when given an empty list" do
      assert_empty Organization.ids_with_organization_projects_disabled([])
    end
  end

  test "project can't be created if owning organization has projects disabled" do
    @org.disable_organization_projects(actor: @owner)
    refute_predicate @org, :organization_projects_enabled?

    project = build(:project, owner: @org, creator: @owner)
    refute_predicate project, :valid?
  end

  context "visible_projects_for" do
    test "includes projects where the viewer has direct access" do
      viewer = create(:user, login: "viewer")
      project = create(:project, owner: @org)
      project.update_org_permission(nil)
      project.update_user_permission(viewer, :read)

      assert_same_elements [project], @org.visible_projects_for(viewer)
    end

    test "includes projects where the viewer has access via a team" do
      viewer = create(:user, login: "viewer")
      @org.add_member(viewer)

      project = create(:project, owner: @org)
      project.update_org_permission(nil)
      project.update_user_permission(viewer, :read)

      team = create(:team, organization: @org)
      team.add_member(viewer)
      team.add_project(project, :read)

      assert_same_elements [project], @org.visible_projects_for(viewer)
    end

    test "includes projects where the viewer has access through org membership" do
      viewer = create(:user, login: "viewer")
      @org.add_member(viewer)

      project = create(:project, owner: @org)
      project.update_org_permission(:read)

      assert_same_elements [project], @org.visible_projects_for(viewer)
    end

    test "includes projects where the viewer has access through org ownership" do
      viewer = create(:user, login: "viewer")
      @org.add_admin(viewer)

      project = create(:project, owner: @org)
      project.update_org_permission(nil)

      assert_same_elements [project], @org.visible_projects_for(viewer)
    end

    test "includes public projects for logged-out users" do
      public_project = create(:project, owner: @org, public: true)
      private_project = create(:project, owner: @org, public: false)

      assert_same_elements [public_project], @org.visible_projects_for(nil)
    end
  end
end
