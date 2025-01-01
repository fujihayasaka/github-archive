# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTradeControlsDependencyTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:user, login: "defunkt",  plan: "medium")
    @org = create(:organization, business: create(:business))
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
  end

  context "#has_any_trade_restrictions?" do
    test "returns true when plan owner has a trade restriction" do
      user = create(:user, :fully_trade_restricted)
      repo = create(:repository, owner: user)
      assert_predicate repo, :has_any_trade_restrictions?
    end

    test "returns false when plan owner has no trade restrictions" do
      user = create(:user)
      repo = create(:repository, owner: user)
      refute_predicate repo, :has_any_trade_restrictions?
    end

    test "can be prefilled efficiently" do
      trade_restricted_user1, trade_restricted_user2 = create_pair(:user, :fully_trade_restricted)
      unrestricted_user1, unrestricted_user2 = create_pair(:user)
      trade_restricted_repo1 = create(:repository, owner: trade_restricted_user1)
      unrestricted_repo1 = create(:repository, owner: unrestricted_user1)
      unrestricted_repo2 = create(:repository, owner: unrestricted_user2)
      trade_restricted_repo2 = create(:repository, owner: trade_restricted_user2)

      # reload the repos so their `owner` isn't loaded yet:
      trade_restricted_repo1 = Repositories::Public.find_active!(trade_restricted_repo1.id)
      trade_restricted_repo2 = Repositories::Public.find_active!(trade_restricted_repo2.id)
      unrestricted_repo1 = Repositories::Public.find_active!(unrestricted_repo1.id)
      unrestricted_repo2 = Repositories::Public.find_active!(unrestricted_repo2.id)

      repos = [trade_restricted_repo1, trade_restricted_repo2, unrestricted_repo1, unrestricted_repo2]

      assert_query_count_per_table({ trade_controls_restrictions: 1, users: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method(repos, :has_any_trade_restrictions?)
      end

      assert_query_count(0) do
        assert_predicate trade_restricted_repo1, :has_any_trade_restrictions?
        assert_predicate trade_restricted_repo2, :has_any_trade_restrictions?
        refute_predicate unrestricted_repo1, :has_any_trade_restrictions?
        refute_predicate unrestricted_repo2, :has_any_trade_restrictions?
      end
    end
  end if GitHub.billing_enabled?

  context "#trade_controls_read_only?" do
    test "returns true if the repo is public and owned by trade control restricted organization" do
      flagged_owner = create(:organization)
      repo          = create(:repository, owner: flagged_owner)

      flagged_owner.trade_controls_restriction.full!

      assert repo.trade_controls_read_only?
    end

    test "returns false if the repo is public and owned by non trade control restricted organization" do
      org_owner = create(:organization)
      repo      = create(:repository, owner: org_owner)

      refute_predicate repo, :trade_controls_read_only?
    end

    test "returns false if the repo is public and owned by user" do
      user_owner = create(:user, :fully_trade_restricted)
      repo       = create(:repository, owner: user_owner)

      refute_predicate repo, :trade_controls_read_only?
    end

    test "returns false if the repo is private" do
      org_owner = create(:organization)
      org_repo  = create(:private_repository, owner: org_owner)
      org_owner.trade_controls_restriction.full!

      user_owner = create(:user)
      user_repo = create(:private_repository, owner: user_owner)
      user_owner.trade_controls_restriction.full!

      refute_predicate org_repo, :trade_controls_read_only?
      refute_predicate user_repo, :trade_controls_read_only?
    end
  end

  test "returns false if the owner has been fully trade restricted" do
    @simple.owner.trade_controls_restriction.full!

    refute @simple.can_privatize?
  end

  test "returns false if the owner has been partially trade restricted" do
    repo = create(:public_repository, owner: @org)
    @org.trade_controls_restriction.partial!

    refute repo.can_privatize?
  end

  test "returns false if the owner has been tier_1 trade restricted" do
    repo = create(:public_repository, owner: @org)
    @org.trade_controls_restriction.tier_1!

    refute repo.can_privatize?
  end

  test "returns true if the owner has been tier_0 trade restricted" do
    repo = create(:public_repository, owner: @org)
    @org.trade_controls_restriction.tier_0!

    assert repo.can_privatize?
  end
end
