# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProjectsDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "visible_projects_for" do
    test "includes all projects when the viewer is the user" do
      public_project = create(:project, owner: @user, public: true)
      private_project = create(:project, owner: @user, public: false)

      assert_same_elements [public_project, private_project], @user.visible_projects_for(@user)
    end

    test "includes all projects that the viewer has been added as a collaborator to" do
      collab = create(:user, login: "collab")
      collab_project = create(:project, owner: @user, name: "collab-project", public: false)
      collab_project.update_user_permission(collab, :read)

      create(:project, owner: @user, name: "noncollab-project", public: false)

      assert_same_elements [collab_project], @user.visible_projects_for(collab)
    end

    test "includes public projects for logged-out users" do
      public_project = create(:project, owner: @user, public: true)
      create(:project, owner: @user, public: false)

      assert_same_elements [public_project], @user.visible_projects_for(nil)
    end

    test "includes no projects when the viewing collaborator is blocked" do
      collab = create(:user, login: "collab")
      collab_project = create(:project, owner: @user, name: "collab-project", public: false)
      @user.block(collab)
      collab_project.update_user_permission(collab, :read)

      create(:project, owner: @user, name: "noncollab-project", public: false)

      assert_empty @user.visible_projects_for(collab)
    end
  end

  context "writable_projects_for" do
    test "includes all projects when the viewer is the user" do
      public_project = create(:project, owner: @user, public: true)
      private_project = create(:project, owner: @user, public: false)

      assert_same_elements [public_project, private_project], @user.writable_projects_for(@user)
    end

    test "includes all projects that the viewer has been added with write access to" do
      write = create(:user, login: "write")
      write_project = create(:project, owner: @user, name: "write-project", public: false)
      write_project.update_user_permission(write, :write)

      create(:project, owner: @user, name: "nonwrite-project", public: false)

      assert_same_elements [write_project], @user.writable_projects_for(write)
    end

    test "includes all projects that the viewer has been added with admin access to" do
      adminable = create(:user, login: "adminable")
      adminable_project = create(:project, owner: @user, name: "adminable-project", public: false)
      adminable_project.update_user_permission(adminable, :admin)

      create(:project, owner: @user, name: "nonadminable-project", public: false)

      assert_same_elements [adminable_project], @user.writable_projects_for(adminable)
    end

    test "excludes projects that the viewer has read only access to" do
      collab = create(:user, login: "collab")
      collab_project = create(:project, owner: @user, name: "collab-project", public: false)
      collab_project.update_user_permission(collab, :read)

      assert_empty @user.writable_projects_for(collab)
    end

    test "excludes public projects for logged-out users" do
      public_project = create(:project, owner: @user, public: true)
      create(:project, owner: @user, public: false)

      assert_empty @user.writable_projects_for(nil)
    end

    test "includes no projects when the viewing collaborator is blocked" do
      collab = create(:user, login: "collab")
      collab_project = create(:project, owner: @user, name: "collab-project", public: false)
      @user.block(collab)
      collab_project.update_user_permission(collab, :read)

      create(:project, owner: @user, name: "noncollab-project", public: false)

      assert_empty @user.writable_projects_for(collab)
    end
  end
end
