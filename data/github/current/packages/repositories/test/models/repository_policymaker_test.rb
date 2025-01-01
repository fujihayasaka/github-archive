# typed: strict
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryPolicymakerTest < GitHub::TestCase
  test "is the repository owner for a public root repository" do
    owner = create(:user)
    repo  = create(:public_repository, owner: owner)

    assert_equal owner, repo.policymaker
  end

  test "is the repository owner for a public fork repository" do
    root_owner = create(:user)
    forker     = create(:user)
    repo       = create(:public_repository, owner: root_owner)

    fork, status = repo.fork(forker: forker)
    assert_equal :created, status
    assert_equal repo, fork.parent

    assert_equal forker, fork.policymaker
  end

  test "is the network owner for a private root repository" do
    owner = create(:user, plan: "micro")
    repo  = create :private_repository, owner: owner

    assert_equal owner, repo.policymaker
  end

  test "is the network owner for a private fork repository" do
    root_owner = create(:user, plan: "micro")
    forker     = create(:user)
    repo       = create :private_repository, owner: root_owner

    repo.add_member(forker)

    fork, status = repo.fork(forker: forker)
    assert_equal :created, status
    assert_equal repo, fork.parent

    assert_equal root_owner, fork.policymaker
  end

  # https://github.com/github/github/pull/86091
  test "does not fail when private fork doesn't have an owner" do
    root_owner = create(:user, plan: "micro")
    forker     = create(:user)
    repo       = create(:private_repository, owner: root_owner)

    repo.add_member(forker)

    fork = create(:fork_repository, forker: forker, fork_repo: repo)
    fork.update_attribute(:owner_id, 0)

    assert_equal root_owner, fork.policymaker
  end
end
