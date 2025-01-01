# typed: strict
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryFilteringTest < GitHub::TestCase
  test "can find only public repositories" do
    user    = create(:user, plan: "micro")
    public  = create(:public_repository, owner: user)
    private = create(:private_repository, owner: user)

    assert_same_elements [public, private], Repository.all
    assert_same_elements [public], Repository.public_scope.all
  end

  test "can find only private repositories" do
    user    = create(:user, plan: "micro")
    public  = create(:public_repository, owner: user)
    private = create(:private_repository, owner: user)

    assert_same_elements [public, private], Repository.all
    assert_same_elements [private], Repository.private_scope.all
  end

  test "can find only internal repositories" do
    internal = create(:internal_repository)
    private = create(:private_repository, owner: internal.owner)
    public = create(:repository, owner: internal.owner)

    assert_same_elements [public, private, internal], Repository.all
    assert_same_elements [internal], Repository.internal_scope.all
  end

  test "can find private without internal repositories" do
    internal = create(:internal_repository)
    private = create(:private_repository, owner: internal.owner)
    public = create(:repository, owner: internal.owner)

    assert_same_elements [public, private, internal], Repository.all
    assert_same_elements [private], Repository.private_not_internal_scope.all
  end

  test "can find only repositories with issues enabled" do
    user           = create(:user)
    with_issues    = create(:repository, owner: user, has_issues: true)
    without_issues = create(:repository, owner: user, has_issues: false)

    assert_same_elements [with_issues, without_issues], Repository.all
    assert_same_elements [with_issues], Repository.with_issues_enabled.all
  end

  test "can find only network root repositories" do
    owner  = create(:user, login: "root-owner")
    repo   = create(:public_repository, owner: owner)
    forker = create(:user, login: "fork-owner")

    fork, status = repo.fork(forker: forker)
    assert_equal :created, status
    assert_equal repo, fork.parent

    assert_same_elements [repo, fork], Repository.all
    assert_same_elements [repo], Repository.network_roots.all
  end

  test "can find only fork repositories" do
    owner  = create(:user, login: "root-owner")
    repo   = create(:public_repository, owner: owner)
    forker = create(:user, login: "fork-owner")

    fork, status = repo.fork(forker: forker)
    assert_equal :created, status
    assert_equal repo, fork.parent

    assert_same_elements [repo, fork], Repository.all
    assert_same_elements [fork], Repository.forks.all
  end

  test "can find only repositories belonging to a specific owner" do
    user      = create(:user, login: "user")
    org       = create(:organization, login: "org")
    user_repo = create(:repository, owner: user)
    org_repo  = create(:repository, owner: org)

    assert_same_elements [user_repo, org_repo], Repository.all
    assert_same_elements [user_repo], Repository.owned_by(user).all
    assert_same_elements [org_repo], Repository.owned_by(org).all
  end

  test "can find only user-owned repositories" do
    user      = create(:user, login: "user")
    org       = create(:organization, login: "org")
    user_repo = create(:repository, owner: user)
    org_repo  = create(:repository, owner: org)

    assert_same_elements [user_repo, org_repo], Repository.all
    assert_same_elements [user_repo], Repository.user_owned.all
  end

  context "Repository#public_or_accessible_by" do
    test "returns accessible repositories" do
      user  = create(:user)
      owner = create(:organization)

      repo_public = create(:repository, name: "repo_public", owner: owner)
      repo_private = create(:private_repository, name: "repo_private", owner: owner)
      repo_private.add_member(user, action: :read)

      assert_same_elements [repo_public], Repository.public_or_accessible_by(nil)
      assert_same_elements [repo_public, repo_private], Repository.public_or_accessible_by(user)
    end

    test "returns no deleted private repositories" do
      user  = create(:user)
      owner = create(:organization)

      repo_public = create(:repository, name: "repo_public", owner: owner)
      repo_private = create(:private_repository, name: "repo_private", owner: owner)
      repo_private.add_member(user, action: :read)
      repo_private.update(active: nil)

      assert_same_elements [repo_public], Repository.public_or_accessible_by(nil)
      assert_same_elements [repo_public], Repository.public_or_accessible_by(user)
    end

    test "returns no deleted public repositories" do
      user  = create(:user)
      owner = create(:organization)

      repo_public = create(:repository, name: "repo_public", owner: owner)
      repo_private = create(:private_repository, name: "repo_private", owner: owner)
      repo_private.add_member(user, action: :read)
      repo_public.update(active: nil)

      assert_same_elements [], Repository.public_or_accessible_by(nil)
      assert_same_elements [repo_private], Repository.public_or_accessible_by(user)
    end
  end
end
