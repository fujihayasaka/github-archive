# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPermissionsDependencyTest < GitHub::TestCase
  fixtures do
    @org  = create(:business_plus_organization)
    @repo = create(:repository, :minimal, owner: @org)
    @custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, base_role_id: Role.write_role.id)

    @maintain_team = create(:public_team, organization: @org)
    @maintain_team.add_repository(@repo, :maintain)

    @child_team = create(:public_team, organization: @org, parent_team_id: @maintain_team.id)
    @child_team.add_repository(@repo, :triage)

    @user = create(:user)
  end

  setup do
    @org.add_member(@user)
  end

  context "#async_action_or_role_level_for" do
    test "returns most capable access level for user" do
      assert @repo.add_member(@user, action: :write)
      assert @maintain_team.add_member(@user)
      assert_equal :maintain, @repo.async_action_or_role_level_for(@user).sync
    end

    test "returns most capable access level for team" do
      assert_equal :maintain, @repo.async_action_or_role_level_for(@child_team).sync
    end

    test "returns role that a user is granted if it is most capable" do
      assert @repo.add_member(@user, action: :admin)
      assert @maintain_team.add_member(@user)
      assert_equal :admin, @repo.async_action_or_role_level_for(@user).sync
    end

    test "returns read for logged out user on public repo" do
      assert_equal :read, @repo.async_action_or_role_level_for(nil).sync
    end

    test "returns nil for logged out user on private repo" do
      priv_repo = create(:private_repository, :minimal)
      assert_nil priv_repo.async_action_or_role_level_for(nil).sync
    end

    test "will return the base role if include_custom_roles is false" do
      assert @repo.add_member(@user, action: @custom_role.name)
      assert_equal @custom_role.base_role.name.to_sym, @repo.async_action_or_role_level_for(@user, include_custom_roles: false).sync
    end

    test "returns custom role even if it has the same ability rank as the base role" do
      assert @repo.add_member(@user, action: @custom_role.name)
      assert_equal @custom_role.name.to_sym, @repo.async_action_or_role_level_for(@user, include_custom_roles: true).sync
    end

    test "returns all repo role if it has greater ability rank as a direct ability" do
      @repo.add_member(@user, action: :read)
      assert @org.grant_org_role(assignee: @user, role: OrganizationRole.all_repo_write_role).success?

      assert_equal OrganizationRole.all_repo_write_role.base_role.name.to_sym, @repo.async_action_or_role_level_for(@user).sync
    end
  end

  context "#async_role_for" do
    test "returns most capable role for a user" do
      assert @repo.add_member(@user, action: :triage)
      assert @maintain_team.add_member(@user)
      assert_equal Role.maintain_role, @repo.async_role_for(@user).sync
    end

    test "returns most capable role for a team" do
      assert_equal Role.maintain_role, @repo.async_role_for(@child_team).sync
    end

    test "returns most capable role from a user in a child team" do
      assert @child_team.add_member(@user)
      assert_equal Role.maintain_role, @repo.async_role_for(@user).sync
    end

    test "returns nil if no role for user" do
      assert_nil @repo.async_role_for(create(:user)).sync
    end

    test "returns the base role of the custom role if include_custom_roles is false" do
      assert @repo.add_member(@user, action: @custom_role.name)
      assert_equal @custom_role.base_role, @repo.async_role_for(@user, false).sync
    end

    test "returns the base role if actor is assigned an All Repo Role" do
      assert @org.grant_org_role(assignee: @user, role: OrganizationRole.all_repo_write_role).success?
      assert_equal OrganizationRole.all_repo_write_role.base_role, @repo.async_role_for(@user, false).sync
    end
  end

  context "async_roles_for" do
    test "returns most capable role for users" do
      user2 = create :user
      assert @repo.add_member(@user, action: :triage)
      assert @repo.add_member(user2, action: :triage)
      assert @maintain_team.add_member(@user)
      assert_same_elements [[@user.id, Role.maintain_role], [user2.id, Role.triage_role]], @repo.async_roles_for([@user, user2]).sync
    end

    test "returns most capable role for a team" do
      assert_equal [[@child_team.id, Role.maintain_role]], @repo.async_roles_for([@child_team]).sync
    end

    test "returns most capable role from a user in a child team" do
      assert @child_team.add_member(@user)
      assert_equal [[@user.id, Role.maintain_role]], @repo.async_roles_for([@user]).sync
    end

    test "returns nil if no role for user" do
      assert_empty @repo.async_roles_for([create(:user)]).sync
    end

    test "returns the base role of the custom role if include_custom_roles is false" do
      assert @repo.add_member(@user, action: @custom_role.name)
      assert_equal [[@user.id, @custom_role.base_role]], @repo.async_roles_for([@user], false).sync
    end

    test "returns the base role if actor is assigned an All Repo Role" do
      assert @org.grant_org_role(assignee: @user, role: OrganizationRole.all_repo_write_role).success?
      assert_equal [[@user.id, OrganizationRole.all_repo_write_role.base_role]], @repo.async_roles_for([@user], false).sync
    end
  end

  context "#async_most_capable_action_or_role_for" do
    test "returns most capable access level for user" do
      assert @repo.add_member(@user, action: :write)
      assert @maintain_team.add_member(@user)
      assert_equal Role.maintain_role, @repo.async_most_capable_action_or_role_for(@user).sync
    end

    test "returns most capable access level for team" do
      assert_equal Role.maintain_role, @repo.async_most_capable_action_or_role_for(@child_team).sync
    end

    test "returns an ability that a user is granted if it is most capable" do
      assert @repo.add_member(@user, action: :admin)
      assert @maintain_team.add_member(@user)
      assert_equal Ability.find_by(actor: @user, subject: @repo), @repo.async_most_capable_action_or_role_for(@user).sync
    end

    test "returns custom role for a user" do
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
      assert @repo.add_member(@user, action: custom_role.name)
      assert_equal custom_role, @repo.async_most_capable_action_or_role_for(@user).sync
    end

    test "returns most capable access for user on team with custom role" do
      custom_role = create(:custom_repository_role, :with_extra_permissions, owner_id: @org.id, owner_type: "Organization", base_role_id: Role.maintain_role.id)
      assert @repo.add_member(@user, action: :write)
      assert @maintain_team.add_member(@user)
      @maintain_team.update_repository_permission(@repo, custom_role.name)
      assert_equal custom_role, @repo.async_most_capable_action_or_role_for(@user).sync
    end
  end
end
