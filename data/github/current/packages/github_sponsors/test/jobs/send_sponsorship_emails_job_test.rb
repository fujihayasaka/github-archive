# typed: true
# frozen_string_literal: true

require "test_helper"

class SendSponsorshipEmailsJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @sponsorship = create(:sponsorship)
    @activity = create(:sponsors_activity,
      sponsor: @sponsorship.sponsor,
      sponsorable: @sponsorship.sponsorable,
      sponsors_tier: @sponsorship.tier,
    )
    @actor = @sponsorship.sponsor
    @tier = @sponsorship.tier
    @listing = @sponsorship.sponsors_listing
  end

  if GitHub.sponsors_enabled?
    test "sends emails when the subscription is active" do
      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "does not send duplicate emails" do
      create(:sponsors_activity, sponsor: @sponsorship.sponsor, sponsorable: @sponsorship.sponsorable,
        sponsors_tier: @sponsorship.tier, timestamp: @activity.timestamp - 5.minutes)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)

      stats = assert_dogstats_increment(2, "#{SendSponsorshipEmailsJob::DATADOG_PREFIX}.skip_duplicate",
        tags: ["patreon:false", "sponsor_type:User", "sponsorable_type:User", "action:new_sponsorship"])
      assert_equal 1, stats.count { |stat| stat.tags.include?("email:new_sponsor") }
      assert_equal 1, stats.count { |stat| stat.tags.include?("email:now_sponsoring") }
    end

    test "will send duplicate emails if enough time has passed" do
      create(:sponsors_activity, sponsor: @sponsorship.sponsor, sponsorable: @sponsorship.sponsorable,
        sponsors_tier: @sponsorship.tier,
        timestamp: @activity.timestamp + (SponsorsActivity::EMAIL_FREQUENCY_IN_MINUTES + 1).minutes)

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)

      refute_dogstats_increment("#{SendSponsorshipEmailsJob::DATADOG_PREFIX}.skip_duplicate")
    end

    test "sends emails when the sponsorship has an active status when FF enabled" do
      @actor.enable_feature(:sponsors_pending_sponsorships)

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "sends emails when the sponsorship has a pending state when FF disabled" do
      pending_sponsorship = create(:sponsorship, :pending)
      pending_sponsorship.sponsor.disable_feature(:sponsors_pending_sponsorships)

      activity = create(:sponsors_activity,
        sponsor: pending_sponsorship.sponsor,
        sponsorable: pending_sponsorship.sponsorable,
        sponsors_tier: pending_sponsorship.tier,
      )

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
    end

    test "does not send emails when the sponsorship has a pending state when FF enabled" do
      pending_sponsorship = create(:sponsorship, :pending)
      pending_sponsorship.sponsor.enable_feature(:sponsors_pending_sponsorships)

      activity = create(:sponsors_activity,
        sponsor: pending_sponsorship.sponsor,
        sponsorable: pending_sponsorship.sponsorable,
        sponsors_tier: pending_sponsorship.tier,
      )

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
    end

    test "sends emails when the subscription is active for an org" do
      sponsorship = create(:sponsorship, sponsorable: create(:organization, :sponsorable))

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "does not send emails when the subscription is inactive" do
      @sponsorship.update(active: false)
      @sponsorship.subscription_item.update(quantity: 0)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "does not send now sponsoring email for sponsorship done via bulk sponsorship" do
      sponsorship = create(:sponsorship, :via_bulk_sponsorship)
      activity = SponsorsActivity.is_new_sponsorship.for_sponsorable_and_sponsor(sponsorship.sponsorable, sponsorship.sponsor).first
      assert_predicate activity, :via_bulk_sponsorship?

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
    end

    test "sends new sponsor email for invoiced sponsorship" do
      transfer = create(
        :invoiced_sponsorship_transfer,
        send_new_sponsor_email_on_transfer: true,
      )
      sponsorship = create(
        :sponsorship,
        :invoiced,
        invoiced_sponsorship_transfer: transfer,
      )
      activity = create(:sponsors_activity,
        sponsor: sponsorship.sponsor,
        sponsorable: sponsorship.sponsorable,
        sponsors_tier: sponsorship.tier,
      )

      refute_predicate transfer, :new_sponsor_email_sent?

      SponsorsPrimerMailer.expects(:new_sponsor).once.returns(stub(deliver_now: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)

      assert_predicate transfer.reload, :new_sponsor_email_sent?
    end

    test "does not send new sponsor email for invoiced sponsorship when opted out" do
      transfer = create(
        :invoiced_sponsorship_transfer,
        send_new_sponsor_email_on_transfer: false,
      )
      sponsorship = create(
        :sponsorship,
        :invoiced,
        invoiced_sponsorship_transfer: transfer,
      )
      activity = create(:sponsors_activity,
        sponsor: sponsorship.sponsor,
        sponsorable: sponsorship.sponsorable,
        sponsors_tier: sponsorship.tier,
      )

      refute_predicate transfer, :new_sponsor_email_sent?

      SponsorsPrimerMailer.expects(:new_sponsor).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)

      refute_predicate transfer.reload, :new_sponsor_email_sent?
    end

    test "sends new sponsor email for concurrent one-time payment" do
      sponsorable = create(:user, :sponsorable)
      sponsorship = create(:sponsorship, sponsorable: sponsorable)
      one_time_tier = create(:sponsors_tier, :published, :one_time,
        sponsors_listing: sponsorable.sponsors_listing
      )
      activity = create(:sponsors_activity,
        sponsor: sponsorship.sponsor,
        sponsorable: sponsorable,
        sponsors_tier: one_time_tier,
      )

      SponsorsPrimerMailer.expects(:new_sponsor)
        .once.with(sponsorship, tier_paid: one_time_tier)
        .returns(stub(deliver_now: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
    end

    test "sends milestone reached email when total sponsors count reaches threshold" do
      SponsorsPrimerMailer.expects(:milestone_reached).once.returns(stub(deliver_later: nil))

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end

      assert_predicate @listing.reload, :milestone_email_sent?
    end

    test "sends milestone reached email when monthly sponsorship amount reaches threshold" do
      SponsorsPrimerMailer.expects(:milestone_reached).once.returns(stub(deliver_later: nil))

      SponsorsMilestone.stub_const(:MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD, @tier.monthly_price_in_dollars) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end

      assert_predicate @listing.reload, :milestone_email_sent?
    end

    test "does not send milestone reached email if sponsorship state is pending when FF enabled" do
      pending_sponsorship = create(:sponsorship, :pending)
      pending_sponsorship.sponsor.enable_feature(:sponsors_pending_sponsorships)

      activity = create(:sponsors_activity,
        sponsor: pending_sponsorship.sponsor,
        sponsorable: pending_sponsorship.sponsorable,
        sponsors_tier: pending_sponsorship.tier,
      )

      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD, pending_sponsorship.tier.monthly_price_in_dollars) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
      end

      refute_predicate pending_sponsorship.sponsors_listing.reload, :milestone_email_sent?
    end

    test "sends milestone reached email when the sponsorship has an active status when FF enabled" do
      @actor.enable_feature(:sponsors_pending_sponsorships)

      SponsorsPrimerMailer.expects(:milestone_reached).once.returns(stub(deliver_later: nil))

      SponsorsMilestone.stub_const(:MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD, @tier.monthly_price_in_dollars) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end

      assert_predicate @listing.reload, :milestone_email_sent?
    end

    test "sends milestone reached email when the sponsorship has a pending state when FF disabled" do
      pending_sponsorship = create(:sponsorship, :pending)
      pending_sponsorship.sponsor.disable_feature(:sponsors_pending_sponsorships)

      activity = create(:sponsors_activity,
        sponsor: pending_sponsorship.sponsor,
        sponsorable: pending_sponsorship.sponsorable,
        sponsors_tier: pending_sponsorship.tier,
      )

      SponsorsPrimerMailer.expects(:milestone_reached).once.returns(stub(deliver_later: nil))

      SponsorsMilestone.stub_const(:MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD, pending_sponsorship.tier.monthly_price_in_dollars) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: activity)
      end

      assert_predicate pending_sponsorship.sponsors_listing.reload, :milestone_email_sent?
    end

    test "does not send milestone reached email when no threshold reached" do
      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 2) do
        SponsorsMilestone.stub_const(:MONTHLY_SPONSORSHIP_AMOUNT_THRESHOLD, @tier.monthly_price_in_dollars + 1) do
          SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
        end
      end

      refute_predicate @listing.reload, :milestone_email_sent?
    end

    test "does not send milestone reached email when listing has a goal" do
      create(:sponsors_goal, :total_sponsors_count, listing: @listing, target_value: 2)

      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end

      refute_predicate @listing.reload, :milestone_email_sent?
    end

    test "does not send milestone reached email when previously sent for listing" do
      @listing.milestone_email_sent!

      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end

      assert_predicate @listing.reload, :milestone_email_sent?
    end

    test "does not send new sponsor email when opted out" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:new_sponsorships)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "does not send new sponsor email when opted out of all" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:all)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:new_sponsor).never
      SponsorsPrimerMailer.expects(:now_sponsoring).once.returns(stub(deliver_later: nil))

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
    end

    test "does not send milestone email when opted out" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:milestone_reached)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end
    end

    test "does not send milestone email when opted out of all" do
      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:all)
      @listing.update_email_opt_outs(email_opt_outs)

      SponsorsPrimerMailer.expects(:milestone_reached).never

      SponsorsMilestone.stub_const(:TOTAL_SPONSORS_COUNT_THRESHOLD, 1) do
        SendSponsorshipEmailsJob.perform_now(sponsors_activity: @activity)
      end
    end

    test "sends Patreon emails when sponsorship is via Patreon" do
      patreon_sponsorship = create(:sponsorship, :patreon)
      patreon_activity = create(:sponsors_activity,
        :patreon,
        sponsor: patreon_sponsorship.sponsor,
        sponsorable: patreon_sponsorship.sponsorable,
        sponsors_tier: patreon_sponsorship.tier,
      )
      SponsorsPrimerMailer.expects(:patreon_now_sponsoring).once.returns(stub(deliver_later: nil))
      SponsorsPrimerMailer.expects(:now_sponsoring).never

      SponsorsPrimerMailer.expects(:patreon_new_sponsor).once.returns(stub(deliver_now: nil))
      SponsorsPrimerMailer.expects(:new_sponsor).never

      SendSponsorshipEmailsJob.perform_now(sponsors_activity: patreon_activity)
    end
  end
end
