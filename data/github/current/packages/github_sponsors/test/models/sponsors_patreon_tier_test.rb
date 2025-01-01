# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsPatreonTierTest < GitHub::TestCase
  context "validations" do
    test "requires campaign_id" do
      patreon_tier = SponsorsPatreonTier.new(campaign_id: "")
      refute_predicate patreon_tier, :valid?
      assert_includes patreon_tier.errors[:campaign_id], "can't be blank"
    end

    test "validates numericality of amount_in_cents" do
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: "dog")

      refute_predicate patreon_tier, :valid?
      assert_includes patreon_tier.errors[:amount_in_cents], "is not a number"
    end

    test "validates amount_in_cents is greater than 0" do
      negative_tier = SponsorsPatreonTier.new(amount_in_cents: -1)
      zero_tier = SponsorsPatreonTier.new(amount_in_cents: 0)

      refute_predicate negative_tier, :valid?
      assert_includes negative_tier.errors[:amount_in_cents], "must be non-zero and cannot exceed $12,000"

      refute_predicate zero_tier, :valid?
      assert_includes zero_tier.errors[:amount_in_cents], "must be non-zero and cannot exceed $12,000"
    end

    test "validates amount_in_cents is within limit" do
      tier = SponsorsPatreonTier.new(amount_in_cents: (SponsorsTier::MAX_SPONSORSHIP_AMOUNT_IN_DOLLARS + 1) * 100)

      refute_predicate tier, :valid?
      assert_includes tier.errors[:amount_in_cents], "must be non-zero and cannot exceed $12,000"
    end

    test "requires sponsors_patreon_user_id" do
      patreon_tier = SponsorsPatreonTier.new(sponsors_patreon_user_id: nil)
      refute_predicate patreon_tier, :valid?
      assert_includes patreon_tier.errors[:sponsors_patreon_user], "must exist"
    end

    test "requires unique amount per sponsors_patreon_user_id + campaign_id pair" do
      patreon_tier1 = create(:sponsors_patreon_tier)
      patreon_tier2 = SponsorsPatreonTier.new(sponsors_patreon_user_id: patreon_tier1.sponsors_patreon_user_id,
        campaign_id: patreon_tier1.campaign_id, amount_in_cents: patreon_tier1.amount_in_cents)
      refute_predicate patreon_tier2, :valid?
      assert_includes patreon_tier2.errors[:amount_in_cents], "has already been taken"
    end

    test "requires amount_in_cents" do
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: nil)
      refute_predicate patreon_tier, :valid?
      assert_includes patreon_tier.errors[:amount_in_cents], "can't be blank"
    end
  end

  context "#name" do
    test "returns human-readable description of the tier amount" do
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: 500)
      assert_equal "$5 a month", patreon_tier.name
    end
  end

  context "#monthly_price_in_cents" do
    test "returns amount_in_cents" do
      amount_in_cents = 123
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: amount_in_cents)
      assert_equal amount_in_cents, patreon_tier.monthly_price_in_cents
    end
  end

  context "#yearly_price_in_cents" do
    test "returns twelve times the amount_in_cents, representing paying for all the months in a year" do
      amount_in_cents = 123
      patreon_tier = SponsorsPatreonTier.new(amount_in_cents: amount_in_cents)
      assert_equal amount_in_cents * 12, patreon_tier.yearly_price_in_cents
    end
  end

  context "#to_money" do
    test "returns a Billing::Money for the amount_in_cents" do
      assert_equal Billing::Money.new(123), SponsorsPatreonTier.new(amount_in_cents: 123).to_money
    end
  end

  context ".with_amount_in_cents scope" do
    test "returns tiers with the exact monthly price specified" do
      lesser_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 123)
      exact_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 456)
      greater_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 789)

      result = SponsorsPatreonTier.with_amount_in_cents(exact_patreon_tier.amount_in_cents)
        .where(id: [lesser_patreon_tier, exact_patreon_tier, greater_patreon_tier])

      refute_includes result, lesser_patreon_tier
      assert_includes result, exact_patreon_tier
      refute_includes result, greater_patreon_tier
    end
  end

  context ".amount_in_cents_less_than scope" do
    test "returns tiers with amount_in_cents less than the given amount" do
      lesser_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 123)
      exact_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 456)
      greater_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 789)

      result = SponsorsPatreonTier.amount_in_cents_less_than(456)

      assert_includes result, lesser_patreon_tier
      refute_includes result, exact_patreon_tier
      refute_includes result, greater_patreon_tier
    end
  end

  context ".amount_in_cents_at_least scope" do
    test "returns tiers with amount_in_cents greater than or equal to the given amount" do
      lesser_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 123)
      exact_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 456)
      greater_patreon_tier = create(:sponsors_patreon_tier, amount_in_cents: 789)

      result = SponsorsPatreonTier.amount_in_cents_at_least(456)

      refute_includes result, lesser_patreon_tier
      assert_includes result, exact_patreon_tier
      assert_includes result, greater_patreon_tier
    end
  end

  test "deletes associated Patreon webhook when the record is destroyed" do
    patreon_tier = create(:sponsors_patreon_tier)
    spu = patreon_tier.sponsors_patreon_user
    patreon_webhook = create(:sponsors_patreon_campaign_webhook, sponsors_patreon_user: spu,
      campaign_id: patreon_tier.campaign_id)

    SponsorsPatreonClient.any_instance.expects(:delete_webhook).once.with(patreon_webhook.webhook_id)

    assert_difference(-> { SponsorsPatreonCampaignWebhook.count }, -1) do
      patreon_tier.destroy!
    end

    refute SponsorsPatreonCampaignWebhook.exists?(patreon_webhook.id)
  end
end
