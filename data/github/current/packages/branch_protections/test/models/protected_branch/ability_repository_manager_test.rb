# typed: true
# frozen_string_literal: true

require "test_helper"

class ProtectedBranchAbilityRepositoryManagerTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "owner")
    @collab = create(:user, login: "collab")
    @org = create(:organization)
    @repository = create(:private_repository, name: "acme", owner: @org)
    @team = create(:team, name: "collaborators", organization: @org)

    @repository.add_member(@user, action: :write)
    @team.add_repository(@repository, :push)
    @team.add_member(@collab)

    @protected_branch = @repository.protect_branch("master",
      creator: @user, restrictions: { users: [@user.login], teams: [@team.slug] }, entry_point: :test_case
    )
  end

  context ".revoke" do
    test "removes access to protected branch" do
      assert @protected_branch.authorized?(@user)
      assert @protected_branch.authorized?(@collab)
      assert_equal [@user, @team], @protected_branch.authorized_actors
      assert_equal [@user], @protected_branch.authorized_users
      assert_equal [@team], @protected_branch.authorized_teams

      ProtectedBranch::AbilityRepositoryManager.revoke(@user, repository: @repository)
      ProtectedBranch::AbilityRepositoryManager.revoke(@team, repository: @repository)

      @protected_branch = ProtectedBranch.find(@protected_branch.id)
      refute @protected_branch.authorized?(@user)
      refute @protected_branch.authorized?(@collab)
      assert_empty @protected_branch.authorized_actors
      assert_empty @protected_branch.authorized_users
      assert_empty @protected_branch.authorized_teams
    end
  end
end
