# typed: true
# frozen_string_literal: true

require "test_helper"

class Repository::TradeControlsTest < GitHub::TestCase
  context "#trade_restricted_by_owner" do
    test "doesn't bomb when no owner" do
      repo = create(:repository)
      repo.update(owner: nil)

      refute repo.trade_restricted_by_owner?

      repo.update(network_id: nil)

      refute repo.trade_restricted_by_owner?
    end
  end

  context "Creating repos" do
    test "fails if the repo is private and the organization has been trade restricted" do
      organization = create(:organization, :fully_trade_restricted)
      repo = build(:private_repository, owner: organization, created_by_user_id: organization.admins.first.id)
      refute repo.save
      assert repo.errors[:trade_controls_restricted_owner].any?, "No trade restricted errors found #{repo.errors}"
      assert_match /can't create repositories/, repo.errors[:trade_controls_restricted_owner].first
    end

    test "fails if the repo is public and the organization has been trade restricted" do
      organization = create(:organization, :fully_trade_restricted)
      repo = build(:repository, owner: organization, created_by_user_id: organization.admins.first.id)
      refute repo.save
      assert repo.errors[:trade_controls_restricted_owner].any?, "No trade restricted errors found #{repo.errors}"
      assert_match /can't create repositories/, repo.errors[:trade_controls_restricted_owner].first
    end

    test "fails if the repo is private and the user has been trade restricted" do
      user = create(:user, :fully_trade_restricted)
      repo = build(:private_repository, owner: user, created_by_user_id: user)
      refute repo.save
      assert repo.errors[:trade_controls_restricted_owner].any?, "No trade restricted errors found #{repo.errors}"
      assert_match /can't create repositories/, repo.errors[:trade_controls_restricted_owner].first
    end

    test "succeeds if the repo is public and the user has been trade restricted" do
      user = create(:user, :fully_trade_restricted)
      repo = build(:repository, owner: user, created_by_user_id: user)
      assert repo.save, "Unable to save repo successfully #{repo.errors.full_messages}"
    end

    test "fails if the user is trade restricted, but the organization is not" do
      organization = create(:organization)
      admin = organization.admin
      admin.trade_controls_restriction.full!
      repo = build(:private_repository, owner: organization, created_by_user_id: admin.id)

      refute repo.save
      assert repo.errors[:trade_controls_restricted_creator].any?, "No trade restricted errors found #{repo.errors}"
      assert_match /can't create repositories/, repo.errors[:trade_controls_restricted_creator].first
    end
  end

  context "Forking repos" do
    test "fails if the new owner is a fully trade restricted organization" do
      organization = create(:organization)
      organization.trade_controls_restriction.full!
      forker = organization.admins.first
      user = create(:user)
      repo = create(:repository, owner: user, created_by_user_id: user)

      repo, result, errors = repo.fork(forker: forker, org: organization)

      refute repo
      assert_equal :invalid, result
      assert errors[:trade_controls_restricted_owner].present?
    end

    test "succeeds if the new owner is a partially trade restricted organization" do
      organization = create(:organization)
      organization.trade_controls_restriction.partial!
      forker = organization.admins.first
      user = create(:user)
      repo = create(:repository, owner: user, created_by_user_id: user)

      repo = create(:fork_repository, forker: forker, fork_repo: repo, organization: organization)

      assert repo
    end

    test "succeeds for public repos if the network owner is trade restricted, but current owner isn't" do
      organization = create(:organization)
      repo         = create(:repository, owner: organization, created_by_user_id: organization.owner)
      forker       = organization.admins.first

      organization.trade_controls_restriction.full!

      repo = create(:fork_repository, forker: forker, fork_repo: repo)

      assert repo
    end
  end
  # Test for whether a repo is disabled for trade restrictions can be found in
  # test/models/repository_test.rb under context "disabled?"
end unless GitHub.enterprise?
