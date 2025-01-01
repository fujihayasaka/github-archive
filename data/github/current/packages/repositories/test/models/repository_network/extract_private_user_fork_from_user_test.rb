# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class ExtractPrivateUserForkFromUserTest < GitHub::TestCase

  fixtures do
    @user = create(:user, plan: "micro")
    @user_repo = create(:private_repository, owner: @user, from_example: :forkable)
    @user_repo.allow_private_repository_forking(actor: @user)
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @user_repo.add_member @user2
    @user_repo.add_member @user3
    @user2_fork = create(:fork_repository, fork_repo: @user_repo, forker: @user2)
    @user3_fork = create(:fork_repository, fork_repo: @user2_fork, forker: @user3)

    @org = create(:organization, plan: "bronze")
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @org_repo = create(:private_repository, owner: @org, from_example: :forkable)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "removes implicit collaborators from the fork and its user-owned descendants" do
    assert @user_repo.pushable_by? @user2
    assert @user_repo.pushable_by? @user3
    assert @user2_fork.pushable_by? @user
    assert @user2_fork.pushable_by? @user3

    assert @user3_fork.pushable_by? @user
    assert @user3_fork.pushable_by? @user2

    @user2_fork.new_extract!(synchronous: true)

    assert @user_repo.reload.pushable_by? @user2
    assert @user_repo.pushable_by? @user3
    refute @user2_fork.reload.pushable_by? @user
    assert @user2_fork.pushable_by? @user3
    DGit.check_replicas @user2_fork

    refute @user3_fork.reload.pushable_by? @user
    assert @user3_fork.pushable_by? @user2
  end
end
