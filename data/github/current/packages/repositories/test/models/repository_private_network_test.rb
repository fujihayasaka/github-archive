
# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryPrivateNetworkTest < GitHub::TestCase
  include RepositoriesTestHelper

  fixtures do
    @root = create(:private_repository, from_example: :simple)
    @user1 = create(:user)
    @user2 = create(:user)
    @user3 = create(:user)
    @user4 = create(:user)
    @user5 = create(:user)

    @root.add_member(@user1)
    @root.add_member(@user2)

    @child1 = create(:fork_repository, fork_repo: @root, forker: @user1)
    @child1.add_member(@user3)
    @child1.add_member(@user4)
    @child1.add_member(@user5)
    create(:fork_repository, fork_repo: @child1, forker: @user3)
    create(:fork_repository, fork_repo: @child1, forker: @user4)
    create(:fork_repository, fork_repo: @child1, forker: @user5)


    @child2 = create(:fork_repository, fork_repo: @root, forker: @user2)
    @child2.add_member(@user3)
    @child2.add_member(@user4)
    @child2.add_member(@user5)
    create(:fork_repository, fork_repo: @child2, forker: @user3)
    create(:fork_repository, fork_repo: @child2, forker: @user4)
    create(:fork_repository, fork_repo: @child2, forker: @user5)

    @public_root = create(:repository, from_example: :simple)

    @org = create(:enterprise_linked_organization)
    @admin = @org.admin
    @org.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @biz_root = create(:private_repository, owner: @org, from_example: :simple)

    @same_biz_org = create(:organization, business: @org.business, admin: @admin)
    @same_biz_org.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @same_biz_child = create(:fork_repository, fork_repo: @biz_root, forker: @admin, owner: @same_biz_org)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "can_attach_to? is false for networks with different visibility" do
    allowed, reason = @root.can_attach_to?(@public_root)
    refute allowed
    assert_equal reason, :visibility

    allowed, reason = @public_root.can_attach_to?(@root)
    refute allowed
    assert_equal reason, :visibility
  end

  test "can_attach_to? is true only when source fork owners have access to destination root" do
    @child1.extract!(synchronous: true)
    user = create(:user)
    @child1.add_member(user)
    @child1.reload

    new_fork = create(:fork_repository, fork_repo: @child1, forker: user)
    allowed, reason = @child1.can_attach_to? @child2
    refute allowed
    assert_equal :dangling_fork, reason
    allowed, reason = @child1.can_attach_to? @root
    refute allowed
    assert_equal :dangling_fork, reason

    @root.add_member(@child1.owner)
    # When there are nested private forks, owners of all repos in the source network need access.
    allowed, reason = @child1.can_attach_to? @child2
    refute allowed
    assert_equal :dangling_fork, reason
    allowed, reason = @child1.can_attach_to? @root
    refute allowed
    assert_equal :dangling_fork, reason

    RepositoryNetwork.forks(@child1.network).each { |fork| @root.add_member(fork.owner) }
    allowed, reason = @child1.can_attach_to? @child2
    assert allowed
    assert_equal :valid, reason
    allowed, reason = @child1.can_attach_to? @root
    assert allowed
    assert_equal :valid, reason
  end

  test "can_attach_to? is true if a new org-owned private fork in the same business would be created" do
    @same_biz_child.extract!(synchronous: true)
    allowed, reason = @same_biz_child.can_attach_to?(@biz_root)
    assert_equal :valid, reason
    assert allowed
  end

  test "can_attach_to? is true if a new org-owned private fork in a different business would be created" do
    different_biz_org = create(:enterprise_linked_organization, admin: @admin)
    different_biz_child = create(:fork_repository, fork_repo: @biz_root, forker: different_biz_org.admin, owner: different_biz_org)
    different_biz_child.extract!(synchronous: true)
    allowed, reason = different_biz_child.can_attach_to?(@biz_root)
    assert allowed
    assert_equal :valid, reason
  end unless GitHub.enterprise?
end
