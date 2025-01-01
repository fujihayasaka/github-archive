# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CreateSponsorshipNewsletterTest < GitHub::TestCase
  include ActionMailer::TestHelper

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

  test "creates a new SponsorshipNewsletter record for the specified sponsorable" do
    newsletter = assert_difference "SponsorshipNewsletter.count", 1 do
      Sponsors::CreateSponsorshipNewsletter.call(@inputs)
    end

    refute_nil newsletter
    assert_equal @sponsorable, newsletter.sponsorable
    assert_equal @sponsorable, newsletter.author
    assert_equal @inputs[:body], newsletter.body
    assert_equal @inputs[:subject], newsletter.subject
    assert_empty newsletter.sponsors_tiers, "should not have set specific tiers, so it would apply to all sponsors"
  end

  test "sends email to all sponsors when no tiers are specified and newsletter is published" do
    sponsor1 = create(:sponsorship, sponsorable: @sponsorable, tier: @default_tier).sponsor
    other_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable.sponsors_listing)
    sponsor2 = create(:sponsorship, sponsorable: @sponsorable, tier: other_tier).sponsor

    expected_text_body = @inputs[:body] + SponsorshipNewsletter.unsubscribe_footer_for(@sponsorable)
    expected_html_body = SponsorshipNewsletter.html_body_for(expected_text_body)
    expected_sponsors = [sponsor1, sponsor2]

    expected_sponsors.each do |sponsor|
      SponsorsMailer.expects(:one_click_unsubscribe_newsletter).once.with(
        sponsorable: @sponsorable,
        sponsor: sponsor,
        subject: @inputs[:subject],
        text_body: expected_text_body,
        html_body: expected_html_body,
      ).returns(stub(deliver_later: nil))
    end

    Sponsors::CreateSponsorshipNewsletter.call(@inputs)
  end

  test "allows setting particular tiers with access and emails only sponsors on those tiers" do
    inputs = @inputs.merge(tier_ids: [@default_tier.id])
    included_sponsor = create(:sponsorship, sponsorable: @sponsorable, tier: @default_tier).sponsor
    other_tier = create(:sponsors_tier, :published, :one_time, sponsors_listing: @sponsorable.sponsors_listing)
    omitted_sponsor = create(:sponsorship, sponsorable: @sponsorable, tier: other_tier).sponsor

    expected_text_body = @inputs[:body] + SponsorshipNewsletter.unsubscribe_footer_for(@sponsorable)
    expected_html_body = SponsorshipNewsletter.html_body_for(expected_text_body)

    SponsorsMailer.expects(:one_click_unsubscribe_newsletter).once.with(
      sponsorable: @sponsorable,
      sponsor: included_sponsor,
      subject: @inputs[:subject],
      text_body: expected_text_body,
      html_body: expected_html_body,
    ).returns(stub(deliver_later: nil))

    newsletter = assert_difference "SponsorshipNewsletter.count", 1 do
      Sponsors::CreateSponsorshipNewsletter.call(inputs)
    end

    assert_equal [@default_tier], newsletter.sponsors_tiers
  end

  test "does not silently ignore tiers not readable by the sponsorable" do
    random_tier = create(:sponsors_tier, :published)
    inputs = @inputs.merge(tier_ids: [random_tier.id, @default_tier.id])

    error = assert_no_difference("SponsorshipNewsletter.count") do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::UnprocessableError) do
        Sponsors::CreateSponsorshipNewsletter.call(inputs)
      end
    end

    assert_equal "Not all selected tiers are valid.", error.message
  end

  test "errors if setting unpublished listing plan" do
    unpublished_tier = create(:sponsors_tier, :draft, sponsors_listing: @sponsorable.sponsors_listing)
    inputs = @inputs.merge(tier_ids: [unpublished_tier.id, @default_tier.id])

    error = assert_no_difference "SponsorshipNewsletter.count" do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::UnprocessableError) do
        Sponsors::CreateSponsorshipNewsletter.call(inputs)
      end
    end

    assert_equal "Could not save the email update: Sponsorship newsletter tiers sponsors tier can not be a draft",
      error.message
  end

  test "errors if the listing has been banned" do
    banned_listing = create(:sponsors_listing, :banned)

    error = assert_no_difference(-> { SponsorshipNewsletter.count }) do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::ForbiddenError) do
        Sponsors::CreateSponsorshipNewsletter.call(sponsorable: banned_listing.sponsorable,
          author: banned_listing.sponsorable, body: "This is the body", subject: "This is the subject")
      end
    end

    assert_equal "Email updates for this Sponsors profile cannot be made at this time.", error.message
  end

  test "errors if the listing is disabled" do
    disabled_listing = create(:sponsors_listing, :disabled)

    error = assert_no_difference(-> { SponsorshipNewsletter.count }) do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::ForbiddenError) do
        Sponsors::CreateSponsorshipNewsletter.call(sponsorable: disabled_listing.sponsorable,
          author: disabled_listing.sponsorable, body: "This is the body", subject: "This is the subject")
      end
    end

    assert_equal "Email updates for this Sponsors profile cannot be made at this time.", error.message
  end

  test "errors if the listing is waitlisted" do
    waitlisted_listing = create(:sponsors_listing, :waitlisted)

    error = assert_no_difference(-> { SponsorshipNewsletter.count }) do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::ForbiddenError) do
        Sponsors::CreateSponsorshipNewsletter.call(sponsorable: waitlisted_listing.sponsorable,
          author: waitlisted_listing.sponsorable, body: "This is the body", subject: "This is the subject")
      end
    end

    assert_equal "Email updates for this Sponsors profile cannot be made at this time.", error.message
  end

  test "errors for author who is not the specified sponsorable user" do
    rando = create(:user)

    error = assert_no_difference(-> { SponsorshipNewsletter.count }) do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::ForbiddenError) do
        Sponsors::CreateSponsorshipNewsletter.call(author: rando, sponsorable: @sponsorable, body: "foo",
          subject: "bar")
      end
    end

    assert_equal "@#{rando} does not have permission to publish a sponsors email update for @#{@sponsorable}.",
      error.message
  end

  test "errors for author who does not have a Sponsors listing" do
    non_sponsorable = create(:user)

    error = assert_no_difference(-> { SponsorshipNewsletter.count }) do
      assert_raises(Sponsors::CreateSponsorshipNewsletter::ForbiddenError) do
        Sponsors::CreateSponsorshipNewsletter.call(author: non_sponsorable, sponsorable: non_sponsorable, body: "foo",
          subject: "bar")
      end
    end

    assert_equal "@#{non_sponsorable} does not have permission to publish a sponsors email update.", error.message
  end

  test "creates a published post by default" do
    newsletter = Sponsors::CreateSponsorshipNewsletter.call(@inputs)
    assert_predicate newsletter, :published?
  end

  test "creates a draft post and does not send any email" do
    assert_no_emails do
      newsletter = Sponsors::CreateSponsorshipNewsletter.call(@inputs.merge(draft: true))
      assert_predicate newsletter, :draft?
    end
  end
end
