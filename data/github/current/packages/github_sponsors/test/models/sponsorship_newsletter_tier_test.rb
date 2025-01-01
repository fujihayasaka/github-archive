# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipNewsletterTierTest < GitHub::TestCase
  setup do
    skip unless GitHub.sponsors_enabled?
  end

  fixtures do
    @sponsorable = create(:user, :sponsorable)
    @newsletter = create(:sponsorship_newsletter, sponsorable: @sponsorable)
  end

  context "validations" do
    test "new newsletter tier is valid for newsletter" do
      newsletter_tier = SponsorshipNewsletterTier.new(
        sponsors_tier: @sponsorable.sponsors_listing.sponsors_tiers.first,
        sponsorship_newsletter: @newsletter,
      )

      assert_predicate newsletter_tier, :valid?
    end

    test "new newsletter tier is valid for newsletter with user without published sponsors listing" do
      user = create(:user, :sponsorable)
      listing = user.sponsors_listing
      listing.state = :draft
      listing.save!

      assert_predicate listing.reload, :draft?

      sponsors_tier = listing.sponsors_tiers.first
      newsletter = create(:sponsorship_newsletter, sponsorable: user)

      newsletter_tier = SponsorshipNewsletterTier.new(
        sponsors_tier: sponsors_tier,
        sponsorship_newsletter: newsletter,
      )

      assert_predicate newsletter_tier, :valid?
    end

    test "record is not valid if tier is a draft" do
      sponsors_tier = create(:sponsors_tier, :draft,
        sponsors_listing: @sponsorable.sponsors_listing, monthly_price_in_cents: 20_00,
        yearly_price_in_cents: 20_00 * 12)

      newsletter_tier = SponsorshipNewsletterTier.new(
        sponsors_tier: sponsors_tier,
        sponsorship_newsletter: @newsletter,
      )

      refute_predicate newsletter_tier, :valid?
    end

    test "record is valid if tier is retired" do
      sponsors_tier = create(:sponsors_tier, :retired,
        sponsors_listing: @sponsorable.sponsors_listing, monthly_price_in_cents: 20_00,
        yearly_price_in_cents: 20_00 * 12)

      newsletter_tier = SponsorshipNewsletterTier.new(
        sponsors_tier: sponsors_tier,
        sponsorship_newsletter: @newsletter,
      )

      assert_predicate newsletter_tier, :valid?
    end
  end
end
