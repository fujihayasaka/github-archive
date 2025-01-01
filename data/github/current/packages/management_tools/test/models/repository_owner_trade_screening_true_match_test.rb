# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryOwnerTradeScreeningTrueMatchTest < GitHub::TestCase
  fixtures do
    skip unless GitHub.billing_enabled?
  end

  test "is true if owner has true match screening status" do
    owner = create(:user)
    profile = create(:account_screening_profile, :true_match, owner: owner)
    repo = create(:repository, owner: owner)

    assert repo.owner_trade_screening_delete_restricted?
  end

  test "is false if owner has no hit screening status" do
    owner = create(:user)
    profile = create(:account_screening_profile, :no_hit, owner: owner)
    repo = create(:private_repository, owner: owner)
    owner.trade_controls_restriction.unrestricted!

    refute repo.owner_trade_screening_delete_restricted?
  end

  test "is false for forked repo if root repo owner has true match screening status but forked repo owner does not" do
    fork_owner, root_owner = create(:user), create(:user)
    root_profile = create(:account_screening_profile, :true_match, owner: root_owner)
    root_repo = create(:repository, owner: root_owner)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)

    assert root_owner.trade_screening_record.true_match?
    refute fork_owner.trade_screening_record.true_match?

    assert root_repo.owner_trade_screening_delete_restricted?
    refute forked_repo.owner_trade_screening_delete_restricted?
  end

  test "is false for forked repo if root owner org has true match screening status but forked repo owner does not" do
    org = create(:organization, :with_corporate_terms)
    fork_owner = org.admins.first
    root_profile = create(:account_screening_profile, :true_match, owner: org)
    org.allow_private_repository_forking(actor: fork_owner)
    root_repo = create(:repository, owner: org)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)

    assert org.trade_screening_record.true_match?
    refute fork_owner.trade_screening_record.true_match?

    assert root_repo.owner_trade_screening_delete_restricted?
    refute forked_repo.owner_trade_screening_delete_restricted?
  end

  test "is true if forked repo owner has true match screening status but root repo owner org does not" do
    org = create(:organization)
    fork_owner = org.admins.first
    fork_profile = create(:account_screening_profile, :true_match, owner: fork_owner)
    org.allow_private_repository_forking(actor: fork_owner)
    root_repo = create(:private_repository, owner: org)
    root_repo.add_member(fork_owner)
    forked_repo = create(:fork_repository, forker: fork_owner, fork_repo: root_repo)
    forked_repo.reload

    assert fork_owner.trade_screening_record.true_match?
    refute org.trade_screening_record.true_match?

    assert forked_repo.owner_trade_screening_delete_restricted?
    refute root_repo.owner_trade_screening_delete_restricted?
  end
end
