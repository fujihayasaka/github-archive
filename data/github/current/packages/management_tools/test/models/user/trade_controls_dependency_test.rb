# typed: true
# frozen_string_literal: true

require "test_helper"

class UserTradeControlsDependencyTest < GitHub::TestCase

  setup do
    @org = create(:organization)
  end

  context "#has_any_trade_restrictions?" do
    test "returns false if ofac_sanctioned? is false" do
      user = create(:user)
      refute_predicate user, :has_any_trade_restrictions?
    end

    test "returns true if ofac_sanctioned? is true" do
      user = create(:user, :fully_trade_restricted)
      assert_predicate user, :has_any_trade_restrictions?
    end
  end if GitHub.billing_enabled?

  context "#has_tier_1_trade_restrictions?" do
    test "returns false if org is not tier_1 trade restricted" do
      org = create(:organization)
      refute_predicate org, :has_tier_1_trade_restrictions?
    end

    test "returns true if org is tier_1 trade restricted" do
      org = create(:organization)
      org.trade_controls_restriction.tier_1!

      assert_predicate org, :has_tier_1_trade_restrictions?
    end
  end if GitHub.billing_enabled?

  context "#has_tier_0_trade_restrictions?" do
    test "returns false if org is not tier_0 trade restricted" do
      org = create(:organization)
      refute_predicate org, :has_tier_0_trade_restrictions?
    end

    test "returns true if org is tier_0 trade restricted" do
      org = create(:organization)
      org.trade_controls_restriction.tier_0!

      assert_predicate org, :has_tier_0_trade_restrictions?
    end
  end if GitHub.billing_enabled?

  context "#has_any_tiered_trade_restrictions?" do
    test "returns false if org is not tier trade restricted" do
      org = create(:organization)
      refute_predicate org, :has_any_tiered_trade_restrictions?
    end

    test "returns true if org is tier_1 trade restricted" do
      org = create(:organization)
      org.trade_controls_restriction.tier_1!

      assert_predicate org, :has_any_tiered_trade_restrictions?
    end

    test "returns true if org is tier_0 trade restricted" do
      org = create(:organization)
      org.trade_controls_restriction.tier_0!

      assert_predicate org, :has_any_tiered_trade_restrictions?
    end
  end if GitHub.billing_enabled?

  context "#ofac_sanctioned?" do
    context "with a restriction record" do
      test "returns true if 'full' trade_controls_restriction" do
        user = create(:user, :fully_trade_restricted)
        assert_predicate user, :has_any_trade_restrictions?
      end

      test "returns true if 'partial' trade_controls_restriction" do
        user = create(:user, :partially_trade_restricted)
        assert_predicate user, :has_any_trade_restrictions?
      end

      test "returns false if 'unrestricted' trade_controls_restriction" do
        user = create(:user, :trade_unrestricted)
        refute_predicate user, :has_any_trade_restrictions?
      end
    end

    context "without a restriction record" do
      test "returns false (behaves as unrestricted)" do
        user = create(:user)

        refute_predicate user, :ofac_sanctioned?
      end
    end
  end if GitHub.billing_enabled?

  context "#restriction_tier_allows_feature?" do
    test "restriction_tier_allows_feature? returns true if organization is not restricted" do
      org = create(:organization)
      assert_predicate org, :restriction_tier_allows_feature?
    end

    test "#restriction_tier_allows_feature? returns false if org is partially restricted" do
      org = create(:organization)

      repository = create(:repository, owner: org)
      org.trade_controls_restriction.partial!

      refute org.restriction_tier_allows_feature?(type: :repository)
    end

    test "#restriction_tier_allows_feature? returns true if organization is tier_0 restricted" do
      org = create(:organization)
      repository = create(:repository, owner: org)
      org.trade_controls_restriction.tier_0!

      assert org.restriction_tier_allows_feature?(type: :repository)
    end

    test "#restriction_tier_allows_feature? returns true if type is nil" do
      org = create(:organization)

      assert org.restriction_tier_allows_feature?(type: nil)
    end

    test "#restriction_tier_allows_feature? returns false if organization is tier_1 restricted" do
      org = create(:organization)

      repository = create(:repository, owner: org)
      org.trade_controls_restriction.tier_1!

      refute org.restriction_tier_allows_feature?(type: :repository)
    end

    test "#restriction_tier_allows_feature? returns false if organization is fully restricted" do
      org = create(:organization)

      repository = create(:repository, owner: org)
      org.trade_controls_restriction.full!

      refute org.restriction_tier_allows_feature?(type: :repository)
    end
  end if GitHub.billing_enabled?

  context "#trade_restriction_finalized?" do
    test "returns true when trade restricted and OFAC downgrade complete" do
      downgrade = create(:ofac_downgrade, :complete)
      user = downgrade.user

      assert_predicate user, :trade_restriction_finalized?
    end

    test "returns false when trade restricted without OFAC downgrade complete" do
      user = create(:user, :fully_trade_restricted)

      refute_predicate user, :trade_restriction_finalized?
    end
  end if GitHub.billing_enabled?

  context "#trade_restriction_finalized_date" do
    test "returns downgrade_on date of complete OFAC downgrade" do
      downgrade_on = Date.parse("2019-07-04")
      downgrade = create(:ofac_downgrade, :complete, downgrade_on: downgrade_on)
      user = downgrade.user

      assert_equal downgrade_on, user.trade_restriction_finalized_date
    end
  end if GitHub.billing_enabled?

  context "#trade_controls_restriction" do
    test "builds an unrestricted restriction if nil" do
      user = create(:user)

      assert_predicate user.trade_controls_restriction, :unrestricted?
      refute_predicate user.trade_controls_restriction, :persisted?
    end

    test "is not autosaved when user is saved" do
      user = create(:user)
      refute_predicate user.trade_controls_restriction, :persisted?

      user.save
      refute_predicate user.trade_controls_restriction, :persisted?
    end

    test "async association also builds a restriction if nil" do
      user = create(:user)

      refute_nil user.async_trade_controls_restriction.sync
    end
  end if GitHub.billing_enabled?
end
