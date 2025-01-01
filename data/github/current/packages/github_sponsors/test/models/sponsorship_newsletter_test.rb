# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorshipNewsletterTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, :sponsorable)
    @email_subject = "Hi!"
    @email_text_body = <<~MARKDOWN
      I just wanted to tell you all thank you for all you've done:
      - I bought a house
      - It was nice
    MARKDOWN

    login = @user.login
    url = "http://#{GitHub.host_name}/sponsors/#{login}"
    @email_text_body_full = @email_text_body + <<~MARKDOWN

      ___

      Unsubscribe by unchecking "Receive email updates from #{login}" at <#{url}>.
    MARKDOWN
    text_helper = FakeHelper.new.extend(TextHelper)
    @email_html_body_full = text_helper.github_flavored_markdown(@email_text_body_full)
    @newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user)

    @listing = @user.sponsors_listing
    @tier = @listing.default_tier

    @other_tier = create(:sponsors_tier, :published,
      sponsors_listing: @listing, monthly_price_in_cents: 20_00, yearly_price_in_cents: 20_00 * 12)

    @sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    @other_sponsor = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    create(:sponsorship, sponsor: @sponsor, sponsorable: @user,
      tier: @tier, is_sponsor_opted_in_to_email: true)
    create(:sponsorship, sponsor: @other_sponsor, sponsorable: @user,
      tier: @other_tier, is_sponsor_opted_in_to_email: true)

    @org_sponsor_admin = create(:user)
    @org_sponsor = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription),
      admin: @org_sponsor_admin)
    @org_sponsor_member = create(:user)
    @org_sponsor.add_member(@org_sponsor_member)
    create(:sponsorship, sponsor: @org_sponsor, sponsorable: @user, tier: @tier, is_sponsor_opted_in_to_email: true)

    @staff = create(:user, :staff)
  end

  test "requires a subject" do
    newsletter = SponsorshipNewsletter.new(subject: nil)
    refute_predicate newsletter, :valid?
    assert_includes newsletter.errors[:subject], "can't be blank"
  end

  test "requires a body" do
    newsletter = SponsorshipNewsletter.new(body: nil)
    refute_predicate newsletter, :valid?
    assert_includes newsletter.errors[:body], "can't be blank"
  end

  test "disallows changing from published state back to draft state" do
    newsletter = create(:sponsorship_newsletter, :published)
    newsletter.state = :draft
    refute_predicate newsletter, :valid?
    assert_includes newsletter.errors[:state], "can't save draft after newsletter has been published"
  end

  context "#for_organization?" do
    test "true for an org's newsletter" do
      org = create(:organization, :sponsorable)
      newsletter = build(:sponsorship_newsletter, sponsorable: org)
      assert_predicate newsletter, :for_organization?
    end

    test "false for a user's newsletter" do
      user = create(:user, :sponsorable)
      newsletter = build(:sponsorship_newsletter, sponsorable: user)
      refute_predicate newsletter, :for_organization?
    end
  end

  # see https://github.com/github/sponsors/issues/5969
  test "allows creating newsletter for custom tier with same amount and frequency as published tier" do
    listing = create(:sponsors_listing, :approved)

    custom_tier = create(:sponsors_tier, :custom, sponsors_listing: listing,
      monthly_price_in_cents: 50_00)

    published_tier = create(:sponsors_tier, :published,
      sponsors_listing: listing, monthly_price_in_cents: custom_tier.monthly_price_in_cents)

    newsletter = SponsorshipNewsletter.new(
      sponsorable: listing.sponsorable,
      author: listing.sponsorable,
      state: :draft,
      body: "body",
      subject: "subject",
    ).tap do |newsletter|
      newsletter.sponsors_tiers = [custom_tier, published_tier]
    end

    result = newsletter.save
    assert_predicate newsletter, :valid?
  end

  if GitHub.sponsors_enabled?
    context "after create/update" do
      test "does not send mailer when draft" do
        SponsorsMailer.expects(:newsletter)
                      .times(0)
                      .returns(stub(deliver_later: nil))
        create(:sponsorship_newsletter, :draft)
      end

      test "sends mailer when created with a published state" do
        sponsorship1 = create(:sponsorship, sponsorable: @user, is_sponsor_opted_in_to_email: true)
        sponsorship2 = create(:sponsorship, :private, sponsorable: @user,
          is_sponsor_opted_in_to_email: true)
        create(:sponsorship, sponsorable: @user, is_sponsor_opted_in_to_email: false)
        create(:sponsorship, :private, sponsorable: @user, is_sponsor_opted_in_to_email: false)
        expected_sponsors = [@sponsor, @other_sponsor, @org_sponsor, sponsorship1.sponsor, sponsorship2.sponsor]

        expected_sponsors.each do |sponsor|
          SponsorsMailer.expects(:one_click_unsubscribe_newsletter).once.with(
            sponsorable: @user,
            sponsor: sponsor,
            subject: @email_subject,
            text_body: @email_text_body_full,
            html_body: @email_html_body_full,
          ).returns(stub(deliver_later: nil))
        end

        create(:sponsorship_newsletter, :published, sponsorable: @user, subject: @email_subject, body: @email_text_body)
      end

      test "sends email to only users on specified tiers" do
        SponsorsMailer.expects(:one_click_unsubscribe_newsletter).once.with(
          sponsorable: @user,
          sponsor: @other_sponsor,
          subject: @email_subject,
          text_body: @email_text_body_full,
          html_body: @email_html_body_full,
        ).returns(stub(deliver_later: nil))

        another_sponsor_user = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))
        another_sponsor = create(:sponsorship,
          sponsor: another_sponsor_user, sponsorable: @user,
          tier: @tier, is_sponsor_opted_in_to_email: true)

        newsletter = create(:sponsorship_newsletter,
          sponsorable: @user, subject: @email_subject, body: @email_text_body,
          sponsors_tiers: [@other_tier])

        newsletter.published!
      end

      test "only sends email to users on specified tiers that are opted in to emails" do
        SponsorsMailer.expects(:one_click_unsubscribe_newsletter).once.with(
          sponsorable: @user,
          sponsor: @other_sponsor,
          subject: @email_subject,
          text_body: @email_text_body_full,
          html_body: @email_html_body_full,
        ).returns(stub(deliver_later: nil))

        non_email_sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))

        create(:sponsorship, sponsor: non_email_sponsor, sponsorable: @user,
          tier: @other_tier, is_sponsor_opted_in_to_email: false)

        newsletter = create(:sponsorship_newsletter,
          sponsorable: @user, subject: @email_subject,
          body: @email_text_body, sponsors_tiers: [@other_tier])

        newsletter.published!
      end

      test "sends mailer when updated to a published state" do
        newsletter = create(:sponsorship_newsletter, :draft)
        create(:sponsorship, sponsorable: newsletter.sponsorable, is_sponsor_opted_in_to_email: true)
        SponsorsMailer.expects(:one_click_unsubscribe_newsletter).times(1).returns(stub(deliver_later: nil))
        newsletter.update_attribute(:state, 1)
      end

      test "doesn't allow a published newsletter to revert to draft state" do
        newsletter = create(:sponsorship_newsletter, :published)
        newsletter.update(state: 0)

        refute_predicate newsletter, :valid?
      end

      test "publishes a NewsletterSent hydro event when newsletter is published" do
        create(:sponsorship, sponsorable: @user)
        newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user)

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          sponsored_developer: Hydro::EntitySerializer.user(@user),
          subject: newsletter.subject,
          body: newsletter.body,
        }

        assert_hydro_published(message, schema: "github.sponsors.v0.NewsletterSent")
      end

      test "doesn't publish a NewsletterSent hydro event when newsletter is draft" do
        create(:sponsorship, sponsorable: @user)
        create(:sponsorship_newsletter, :draft, sponsorable: @user)

        refute_hydro_messages(schema: "github.sponsors.v0.NewsletterSent")
      end

      test "instruments newsletter sent when a newsletter is published" do
        create(:sponsorship, sponsorable: @user)

        events = subscribe "sponsors.sponsored_developer_update_newsletter_send"
        newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user)

        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          sponsorship_newsletter_id: newsletter.id,
        }
        assert_equal events.size, 1
        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "doesn't instrument newsletter sent when a newsletter is draft" do
        create(:sponsorship, sponsorable: @user)

        events = subscribe "sponsors.sponsored_developer_update_newsletter_send"
        create(:sponsorship_newsletter, :draft, sponsorable: @user)

        assert_empty events
      end
    end

    context ".html_body_for" do
      # https://github.com/github/sponsors/issues/2862
      test "displays unsubscribe footer without adding h2 tags" do
        text_body = <<~TEXT
          We artists are a different breed of people. We're a happy bunch. Be careful. You can always add more - but you can't take it away. The first step to doing anything is to believe you can do it. See it finished in your mind before you ever start.
          You can do it. Almost everything is going to happen for you automatically - you don't have to spend any time working or worrying. Isn't that fantastic that you can create an almighty tree that fast? We're trying to teach you a technique here and how to use it. Those great big fluffy clouds.
          See. We take the corner of the brush and let it play back-and-forth. We'll put a happy little bush here. Automatically, all of these beautiful, beautiful things will happen. See there, told you that would be easy. We need dark in order to show light.
        TEXT

        text_body += SponsorshipNewsletter.unsubscribe_footer_for(@user)

        html_body = SponsorshipNewsletter.html_body_for(text_body)

        assert_includes html_body, "hr"
        refute_includes html_body, "h2"
      end
    end

    context "#readable_by?" do
      test "true for user sponsorable for published newsletter" do
        assert @newsletter.readable_by?(@user)
      end

      test "true for user sponsorable for draft newsletter" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        assert draft_newsletter.readable_by?(@user)
      end

      test "true for admin of org sponsorable for published newsletter" do
        org_admin = create(:user)
        org = create(:organization, :sponsorable, admin: org_admin)
        newsletter = create(:sponsorship_newsletter, :published, sponsorable: org)
        assert newsletter.readable_by?(org_admin)
      end

      test "true for admin of org sponsorable for draft newsletter" do
        org_admin = create(:user)
        org = create(:organization, :sponsorable, admin: org_admin)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: org)
        assert draft_newsletter.readable_by?(org_admin)
      end

      test "true for active sponsor for published newsletter" do
        assert @newsletter.readable_by?(@sponsor)
      end

      test "false for member of active org sponsor for published newsletter" do
        refute @newsletter.readable_by?(@org_sponsor_member)
      end

      test "true for admin of active org sponsor for published newsletter" do
        assert @newsletter.readable_by?(@org_sponsor_admin)
      end

      test "false for active sponsor for published newsletter that's for a specific tier sponsor is not using" do
        tier_newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user,
          sponsors_tiers: [@other_tier])
        refute tier_newsletter.readable_by?(@sponsor)
      end

      test "true for active sponsor for published newsletter that's for a specific tier sponsor is using" do
        tier_newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user,
          sponsors_tiers: [@other_tier])
        assert tier_newsletter.readable_by?(@other_sponsor)
      end

      test "false for active sponsor for draft newsletter" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        refute draft_newsletter.readable_by?(@sponsor)
      end

      test "false for non-sponsor for published newsletter" do
        user = create(:user)
        refute @newsletter.readable_by?(user)
      end

      test "false for non-sponsor for draft newsletter" do
        user = create(:user)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        refute draft_newsletter.readable_by?(user)
      end

      test "false for anonymous viewer for published newsletter" do
        refute @newsletter.readable_by?(nil)
      end

      test "false for anonymous viewer for draft newsletter" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        refute draft_newsletter.readable_by?(nil)
      end

      test "false for past sponsor whose sponsorship is now inactive for published newsletter" do
        sponsorship = create(:sponsorship, :inactive, sponsorable: @user)
        refute @newsletter.readable_by?(sponsorship.sponsor)
      end

      test "false for past sponsor whose sponsorship is now inactive for draft newsletter" do
        sponsorship = create(:sponsorship, :inactive, sponsorable: @user)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        refute draft_newsletter.readable_by?(sponsorship.sponsor)
      end
    end

    context "visible_to scope" do
      test "includes published newsletter for user sponsorable" do
        result = SponsorshipNewsletter.visible_to(@user)
        assert_includes result, @newsletter
      end

      test "includes draft newsletter for user sponsorable" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        result = SponsorshipNewsletter.visible_to(@user)
        assert_includes result, draft_newsletter
      end

      test "includes published newsletter for admin of org sponsorable" do
        org_admin = create(:user)
        org = create(:organization, :sponsorable, admin: org_admin)
        newsletter = create(:sponsorship_newsletter, :published, sponsorable: org)

        result = SponsorshipNewsletter.visible_to(org_admin)

        assert_includes result, newsletter
      end

      test "includes draft newsletter for admin of org sponsorable" do
        org_admin = create(:user)
        org = create(:organization, :sponsorable, admin: org_admin)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: org)

        result = SponsorshipNewsletter.visible_to(org_admin)

        assert_includes result, draft_newsletter
      end

      test "includes published newsletter for active sponsor" do
        result = SponsorshipNewsletter.visible_to(@sponsor)
        assert_includes result, @newsletter
      end

      test "includes published newsletter for sponsorable when Sponsors listing is not approved" do
        @listing.update!(state: :draft)
        result = SponsorshipNewsletter.visible_to(@user)
        assert_includes result, @newsletter
      end

      test "omits published newsletter for active sponsor when Sponsors listing is not approved" do
        @listing.update!(state: :draft)
        result = SponsorshipNewsletter.visible_to(@sponsor)
        refute_includes result, @newsletter
      end

      test "omits published newsletter for member of active org sponsor" do
        result = SponsorshipNewsletter.visible_to(@org_sponsor_member)
        refute_includes result, @newsletter
      end

      test "includes published newsletter for admin of active org sponsor" do
        result = SponsorshipNewsletter.visible_to(@org_sponsor_admin)
        assert_includes result, @newsletter
      end

      test "omits published newsletter that's for a specific tier sponsor is not using for active sponsor" do
        tier_newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user,
          sponsors_tiers: [@other_tier])
        result = SponsorshipNewsletter.visible_to(@sponsor)
        refute_includes result, tier_newsletter
      end

      test "includes published newsletter that's for a specific tier sponsor is using" do
        tier_newsletter = create(:sponsorship_newsletter, :published, sponsorable: @user,
          sponsors_tiers: [@other_tier])
        result = SponsorshipNewsletter.visible_to(@other_sponsor)
        assert_includes result, tier_newsletter
      end

      test "omits draft newsletter for active sponsor" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        result = SponsorshipNewsletter.visible_to(@sponsor)
        refute_includes result, draft_newsletter
      end

      test "omits published newsletter for non-sponsor" do
        user = create(:user)
        result = SponsorshipNewsletter.visible_to(user)
        refute_includes result, @newsletter
      end

      test "omits draft newsletter for non-sponsor" do
        user = create(:user)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)

        result = SponsorshipNewsletter.visible_to(user)

        refute_includes result, draft_newsletter
      end

      test "omits published newsletter for anonymous viewer" do
        result = SponsorshipNewsletter.visible_to(nil)
        refute_includes result, @newsletter
      end

      test "omits draft newsletter for anonymous viewer" do
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)
        result = SponsorshipNewsletter.visible_to(nil)
        refute_includes result, draft_newsletter
      end

      test "omits published newsletter for past sponsor whose sponsorship is now inactive" do
        sponsorship = create(:sponsorship, :inactive, sponsorable: @user)
        result = SponsorshipNewsletter.visible_to(sponsorship.sponsor)
        refute_includes result, @newsletter
      end

      test "omits draft newsletter for past sponsor whose sponsorship is now inactive" do
        sponsorship = create(:sponsorship, :inactive, sponsorable: @user)
        draft_newsletter = create(:sponsorship_newsletter, :draft, sponsorable: @user)

        result = SponsorshipNewsletter.visible_to(sponsorship.sponsor)

        refute_includes result, draft_newsletter
      end

      # https://github.com/github/sponsors/issues/4565
      test "includes each newsletter only once" do
        listing = create(:sponsors_listing, :for_org, tier_count: 2)
        tier1, tier2 = listing.published_sponsors_tiers
        org_sponsorable = listing.sponsorable
        org_admin = org_sponsorable.admin
        newsletter1 = create(:sponsorship_newsletter, :published, sponsorable: org_sponsorable,
          author: org_admin, sponsors_tiers: [tier1, tier2])
        newsletter2 = create(:sponsorship_newsletter, :published, sponsorable: org_sponsorable,
          author: org_admin)

        result = SponsorshipNewsletter.visible_to(org_admin)

        assert_same_elements [newsletter1, newsletter2], result
      end
    end

    context "#async_author_for" do
      test "returns author regardless of the viewer when author is not spammy" do
        author = create(:user)
        newsletter = create(:sponsorship_newsletter, sponsorable: @user, author: author)

        assert_equal author, newsletter.async_author_for(viewer: @sponsor).sync
        assert_equal author, newsletter.async_author_for(viewer: @user).sync
        assert_equal author, newsletter.async_author_for(viewer: author).sync
        assert_equal author, newsletter.async_author_for(viewer: nil).sync
        assert_equal author, newsletter.async_author_for(viewer: @staff).sync
      end

      test "returns spammy author only when viewer can see the spammer", spammy_only: true do
        author = create(:spammy_user)
        newsletter = create(:sponsorship_newsletter, sponsorable: @user, author: author)

        assert_nil newsletter.async_author_for(viewer: @sponsor).sync
        assert_nil newsletter.async_author_for(viewer: @user).sync
        assert_equal author, newsletter.async_author_for(viewer: author).sync
        assert_nil newsletter.async_author_for(viewer: nil).sync
        assert_equal author, newsletter.async_author_for(viewer: @staff).sync
      end

      test "returns nil regardless of the viewer when author has been deleted" do
        author = create(:user)
        newsletter = create(:sponsorship_newsletter, sponsorable: @user, author: author)
        author.delete

        assert_nil newsletter.reload.async_author_for(viewer: @sponsor).sync
        assert_nil newsletter.async_author_for(viewer: @user).sync
        assert_nil newsletter.async_author_for(viewer: author).sync
        assert_nil newsletter.async_author_for(viewer: nil).sync
        assert_nil newsletter.async_author_for(viewer: @staff).sync
      end
    end

    context "destroying" do
      test "destroys associated sponsorship_newsletter_tiers records" do
        newsletter_tier_record = create(:sponsorship_newsletter_tier,
          sponsorship_newsletter: @newsletter, tier: @tier)

        @newsletter.destroy!
        assert_nil SponsorshipNewsletterTier.find_by(id: newsletter_tier_record.id)
      end
    end

    context "#sponsors_with_access" do
      test "returns sponsors that have access to a newsletter" do
        other_sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))
        create(:sponsorship, sponsor: other_sponsor, sponsorable: @user, tier: @tier,
          is_sponsor_opted_in_to_email: true)

        assert_same_elements [@sponsor, @other_sponsor, @org_sponsor, other_sponsor], @newsletter.sponsors_with_access
      end

      test "returns all sponsors if newsletter is not restricted to certain tiers" do
        other_sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))
        another_sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))

        [other_sponsor, another_sponsor].each do |user|
          create(:sponsorship, sponsor: user, sponsorable: @user, is_sponsor_opted_in_to_email: true)
        end

        newsletter = create(:sponsorship_newsletter, sponsorable: @user)

        result = newsletter.sponsors_with_access

        assert_equal 5, result.size
        assert_equal @sponsor, result.first
        assert_equal @other_sponsor, result.second
        assert_equal @org_sponsor, result.third
        assert_equal other_sponsor, result.fourth
        assert_equal another_sponsor, result.fifth
      end

      test "returns sponsors for the newsletter's tiers" do
        newsletter = create(:sponsorship_newsletter, :with_tier, tier: @tier, sponsorable: @user)

        result = newsletter.sponsors_with_access

        assert_equal 2, result.size
        assert_includes result, @sponsor
        refute_includes result, @other_sponsor
        assert_includes result, @org_sponsor
      end

      test "returns only sponsors who are opted into email" do
        non_email_sponsor = create(:credit_card_user,
          plan_subscription: create(:billing_plan_subscription))

        create(:sponsorship, sponsor: non_email_sponsor, sponsorable: @user,
          tier: @tier, is_sponsor_opted_in_to_email: false)

        result = @newsletter.sponsors_with_access

        assert_equal 3, result.size
        assert_equal @sponsor, result.first
        assert_equal @other_sponsor, result.second
        assert_equal @org_sponsor, result.third
      end
    end

    context "#for_all_tiers?" do
      test "returns true if newsletter is for all tiers to access" do
        assert_predicate @newsletter, :for_all_tiers?
      end

      test "returns false if newsletter is for specific tiers" do
        newsletter = create(:sponsorship_newsletter,
          sponsorable: @user,
          subject: @email_subject,
          body: @email_text_body,
          sponsors_tiers: [@other_tier],
        )

        refute_predicate newsletter, :for_all_tiers?
      end
    end
  end
end
