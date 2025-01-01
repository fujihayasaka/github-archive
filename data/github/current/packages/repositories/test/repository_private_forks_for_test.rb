# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPrivateForksForTest < GitHub::TestCase
  fixtures do
    @org_owner = create(:user)
    @org = create :organization, admin: @org_owner
    @org.allow_private_repository_forking(actor: @org_owner)
    @repo = create :private_repository, owner: @org

    @user = create(:user)
    @org.add_member(@user)

    # create a fork and delete it, which should not be returned
    deleted_fork, reason = @repo.fork(forker: @user)
    deleted_fork.remove(User.ghost, synchronous: true)

    @user_fork, reason = @repo.fork(forker: @user)
  end

  test "returns a users forks of an organizations private repositories" do
    forks = Repository.private_forks_for(
              organization: @org, belonging_to_user: @user,
            )
    assert_equal 1, forks.count
    assert_includes forks, @user_fork
  end

  test "doesn't return users other forks or repos" do
    @repo2 = create(:repository)
    @user_fork2, reason = @repo2.fork(forker: @user)
    forks = Repository.private_forks_for(
              organization: @org, belonging_to_user: @user,
            )
    assert_equal 1, forks.count
    assert_includes forks, @user_fork
  end

  test "doesn't return other forks in this org not belonging to this user" do
    @org_owner_fork, reason = @repo.fork(forker: @org_owner)
    forks = Repository.private_forks_for(
              organization: @org, belonging_to_user: @user,
            )
    assert_equal 1, forks.count
    assert_includes forks, @user_fork
  end
end
