# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryTradeRestrictedByOwnerTest < GitHub::TestCase
  test "is true if owner is trade restricted" do
    owner = create(:user)
    repo = create(:repository, owner: owner)
    owner.trade_controls_restriction.full!

    assert repo.trade_restricted_by_owner?
  end

  test "is true if repo root owner is trade restricted" do
    fork_owner, root_owner = create(:user), create(:user)
    root_repo = create(:repository, owner: root_owner)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)
    root_owner.trade_controls_restriction.full!

    assert root_repo.trade_restricted_by_owner?
    assert forked_repo.trade_restricted_by_owner?
  end

  test "is true if root owner is a trade restricted organization" do
    org = create(:organization)
    fork_owner = org.admins.first
    org.allow_private_repository_forking(actor: fork_owner)
    root_repo = create(:repository, owner: org)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)
    org.trade_controls_restriction.full!

    assert root_repo.trade_restricted_by_owner?
    assert forked_repo.trade_restricted_by_owner?
  end

  test "is true if fork owner is trade restricted" do
    org = create(:organization)
    fork_owner = org.admins.first
    org.allow_private_repository_forking(actor: fork_owner)
    root_repo = create(:private_repository, owner: org)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)
    fork_owner.trade_controls_restriction.full!
    forked_repo.reload

    assert forked_repo.trade_restricted_by_owner?
    refute root_repo.trade_restricted_by_owner?
  end

  test "is false if owner is not trade restricted" do
    owner = create(:user)
    repo = create(:private_repository, owner: owner)
    owner.trade_controls_restriction.unrestricted!

    refute repo.trade_restricted_by_owner?
  end
end
