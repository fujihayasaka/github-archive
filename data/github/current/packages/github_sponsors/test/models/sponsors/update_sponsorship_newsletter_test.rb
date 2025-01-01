# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::UpdateSponsorshipNewsletterTest < GitHub::TestCase
  fixtures do
    @sponsorable = create(:user, :sponsorable)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    @default_tier = @sponsorable.sponsors_listing.default_tier
    @inputs = {
      sponsorable: @sponsorable,
      author: @sponsorable,
      body: "This is the body",
      subject: "This is the subject",
    }
  end

  test "updates a new SponsorshipNewsletter record" do
    newsletter = create(:sponsorship_newsletter, :draft, author: @sponsorable,
                        subject: "Before subject", body: "Before body",
                        sponsorable: @sponsorable)
    assert_equal newsletter.subject, "Before subject"
    assert_equal newsletter.body, "Before body"

    inputs = {
      newsletter: newsletter,
      subject: "After subject",
      body: "After body",
      draft: true,
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)

    refute_nil result.newsletter
    updated_newsletter = T.must(result.newsletter)
    assert_equal updated_newsletter.id, newsletter.id
    assert_equal updated_newsletter.subject, "After subject"
    assert_equal updated_newsletter.body, "After body"
  end

  test "Raises validation error if the newsletter is already published" do
    newsletter = create(:sponsorship_newsletter, :published, author: @sponsorable,
                        sponsorable: @sponsorable)

    inputs = {
      newsletter: newsletter,
      subject: "Update subject",
      body: "Update body",
      draft: true,
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)

    refute_nil result.error
    assert_equal "You can't update a published sponsorship update.", T.must(result.error).message
  end

  test "allows setting Sponsors tiers for newsletter" do
    newsletter = create(:sponsorship_newsletter, :draft, author: @sponsorable,
                        sponsorable: @sponsorable)
    inputs = {
      newsletter: newsletter,
      subject: "Update subject",
      body: "Update body",
      draft: true,
      tier_ids: [@default_tier.id],
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)

    refute_nil result.newsletter
    updated_newsletter = T.must(result.newsletter)
    tiers = updated_newsletter.sponsors_tiers

    assert_equal newsletter.id, updated_newsletter.id
    assert_equal "Update subject", updated_newsletter.subject
    assert_equal "Update body", updated_newsletter.body
    assert_equal @default_tier.id, T.must(tiers.first).id
  end

  test "allows removing all tiers from newsletter" do
    newsletter = create(:sponsorship_newsletter, :draft,
      author: @sponsorable,
      sponsorable: @sponsorable,
      sponsors_tiers: [@default_tier]
    )

    assert_equal [@default_tier], newsletter.sponsors_tiers

    inputs = {
      newsletter: newsletter,
      subject: "Update subject",
      body: "Update body",
      draft: true,
      tier_ids: [],
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)

    refute_nil result.newsletter
    updated_newsletter = T.must(result.newsletter)
    assert_empty updated_newsletter.sponsors_tiers

    assert_equal newsletter.id, updated_newsletter.id
    assert_equal "Update subject", updated_newsletter.subject
    assert_equal "Update body", updated_newsletter.body
    assert_empty newsletter.reload.sponsors_tiers
  end

  test "allows removing some tiers from newsletter" do
    other_tier = create(:sponsors_tier, :published, listing: @sponsorable.sponsors_listing)
    newsletter = create(:sponsorship_newsletter, :draft,
      author: @sponsorable,
      sponsorable: @sponsorable,
      sponsors_tiers: [@default_tier, other_tier]
    )

    assert_equal [@default_tier, other_tier], newsletter.sponsors_tiers

    inputs = {
      newsletter: newsletter,
      subject: "Update subject",
      body: "Update body",
      tier_ids: [@default_tier.id],
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)

    refute_nil result.newsletter
    updated_newsletter = T.must(result.newsletter)
    tiers = updated_newsletter.sponsors_tiers

    assert_equal newsletter.id, updated_newsletter.id
    assert_equal "Update subject", updated_newsletter.subject
    assert_equal "Update body", updated_newsletter.body
    assert_equal @default_tier.id, T.must(tiers.first).id
    assert_includes newsletter.sponsors_tiers, @default_tier
    refute_includes newsletter.sponsors_tiers, other_tier
  end

  test "errors if setting unpublished tier" do
    unpublished_tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsorable.sponsors_listing)

    newsletter = create(:sponsorship_newsletter, :draft,
      author: @sponsorable,
      sponsorable: @sponsorable
    )

    inputs = {
      newsletter: newsletter,
      subject: "Update subject",
      body: "Update body",
      tier_ids: [@default_tier.id, unpublished_tier.id],
    }

    result = Sponsors::UpdateSponsorshipNewsletter.call(**inputs)
    refute_nil result.error
    assert_equal "Could not update sponsorship update: Validation failed: Sponsors tier can not be a draft",
      T.must(result.error).message
  end
end
