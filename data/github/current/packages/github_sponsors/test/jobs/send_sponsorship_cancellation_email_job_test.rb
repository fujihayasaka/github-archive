# typed: true
# frozen_string_literal: true

require "test_helper"

class SendSponsorshipCancellationEmailJobTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include DogstatsTestHelpers

  if GitHub.sponsors_enabled?
    test "sends email" do
      sponsors_activity = create(:sponsors_activity)

      assert_emails 1 do
        SendSponsorshipCancellationEmailJob.perform_now(
          sponsors_activity: sponsors_activity,
        )
      end
    end

    test "does not send duplicate emails" do
      activity = create(:sponsors_activity, :cancelled_sponsorship)
      create(:sponsors_activity, :cancelled_sponsorship, sponsor: activity.sponsor, sponsorable: activity.sponsorable,
        old_sponsors_tier: activity.old_sponsors_tier, timestamp: activity.timestamp - 5.minutes)

      SponsorsPrimerMailer.expects(:sponsorship_cancellation_notice).never

      SendSponsorshipCancellationEmailJob.perform_now(sponsors_activity: activity)

      assert_dogstats_increment(1, "#{SendSponsorshipCancellationEmailJob::DATADOG_PREFIX}.skip_duplicate",
        tags: ["patreon:false", "sponsor_type:User", "sponsorable_type:User", "action:cancelled_sponsorship",
          "email:sponsorship_cancellation_notice"])
    end

    test "does not send email when opted out" do
      sponsors_activity = create(:sponsors_activity)
      sponsorable = sponsors_activity.sponsorable

      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:cancelled_sponsorships)
      sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

      assert_emails 0 do
        SendSponsorshipCancellationEmailJob.perform_now(
          sponsors_activity: sponsors_activity,
        )
      end
    end

    test "does not send email when opted out of all" do
      sponsors_activity = create(:sponsors_activity)
      sponsorable = sponsors_activity.sponsorable

      email_opt_outs = SponsorsEmailOptOuts.new(bitmask: nil)
      email_opt_outs.opt_out_of(:all)
      sponsorable.sponsors_listing.update_email_opt_outs(email_opt_outs)

      assert_emails 0 do
        SendSponsorshipCancellationEmailJob.perform_now(
          sponsors_activity: sponsors_activity,
        )
      end
    end

    test "does not send email when SponsorsListing does not exist" do
      sponsors_activity = create(:sponsors_activity)
      sponsors_activity.sponsors_listing.delete

      assert_emails 0 do
        SendSponsorshipCancellationEmailJob.perform_now(sponsors_activity: sponsors_activity.reload)
      end
    end
  else
    test "does not send email if sponsors are disabled" do
      sponsors_activity = create(:sponsors_activity)

      assert_emails 0 do
        SendSponsorshipCancellationEmailJob.perform_now(
          sponsors_activity: sponsors_activity,
        )
      end
    end
  end
end
