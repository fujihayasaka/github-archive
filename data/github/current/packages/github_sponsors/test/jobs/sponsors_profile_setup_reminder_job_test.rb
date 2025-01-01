# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.sponsors_enabled?
  class SponsorsProfileSetupReminderJobTest < GitHub::TestCase
    context "30 days after signup" do
      test "emails the sponsorable user" do
        eligible = create(:sponsors_listing, :draft, :matchable, accepted_at: Time.now)

        SponsorsPrimerMailer.expects(:first_profile_setup_reminder)
          .once
          .with(sponsorable: eligible.sponsorable)
          .returns(stub(deliver_now: nil))

        travel_to(30.days.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end

      test "emails the sponsorable org" do
        eligible = create(:sponsors_listing, :draft, :matchable, :for_org, accepted_at: Time.now)

        SponsorsPrimerMailer.expects(:first_profile_setup_reminder)
          .once
          .with(sponsorable: eligible.sponsorable)
          .returns(stub(deliver_now: nil))

        travel_to(30.days.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end

      test "does nothing if the membership is not match eligible" do
        not_eligible = create(:sponsors_listing, :waitlisted)

        SponsorsPrimerMailer.expects(:first_profile_setup_reminder).never

        travel_to(30.days.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end
    end

    context "7 weeks after signup" do
      test "emails the sponsorable user" do
        eligible = create(:sponsors_listing, :draft, :matchable, accepted_at: Time.now)

        SponsorsPrimerMailer.expects(:second_profile_setup_reminder)
          .once
          .with(sponsorable: eligible.sponsorable)
          .returns(stub(deliver_now: nil))

        travel_to(7.weeks.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end

      test "emails the sponsorable org" do
        eligible = create(:sponsors_listing, :draft, :matchable, :for_org, accepted_at: Time.now)

        SponsorsPrimerMailer.expects(:second_profile_setup_reminder)
          .once
          .with(sponsorable: eligible.sponsorable)
          .returns(stub(deliver_now: nil))

        travel_to(7.weeks.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end

      test "does nothing if the membership is not match eligible" do
        not_eligible = create(:sponsors_listing, :waitlisted)

        SponsorsPrimerMailer.expects(:second_profile_setup_reminder).never

        travel_to(7.weeks.from_now) do
          SponsorsProfileSetupReminderJob.perform_now
        end
      end
    end
  end
end
