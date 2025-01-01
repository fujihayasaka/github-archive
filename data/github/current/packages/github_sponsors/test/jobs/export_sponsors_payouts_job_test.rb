# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorsPayoutsJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      @org_listing = create(:sponsors_listing, :approved, :fiscal_host, :with_stripe_account)
      @sponsorable = @org_listing.sponsorable
    end

    setup do
      SponsorsListing::PayoutsExport
        .any_instance
        .stubs(:as_csv)
        .returns(SponsorsListing::PayoutsExport::CSV_HEADERS.join(",") + "\n")
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: ExportSponsorsPayoutsJob, args: [@sponsorable, {
        payout_id: "payout_id",
      }]
    end

    context "#perform" do
      test "calls the mailer with the export data" do
        travel_to("2021-04-01") do
          actor = @sponsorable.admins.first
          SponsorsPrimerMailer
            .expects(:payouts_export)
            .once
            .with(
              sponsorable: @sponsorable,
              filename: "sponsors-#{@sponsorable}-payouts-2021-04-01.csv",
              export_content: SponsorsListing::PayoutsExport::CSV_HEADERS.join(",") + "\n",
              actor: actor,
              recipient: nil,
            )
            .returns(stub(deliver_later: nil))

          Failbot
            .expects(:report)
            .never

          ExportSponsorsPayoutsJob.perform_now(
            @sponsorable,
            payout_id: "payout_id",
            actor: actor,
          )
        end
      end

      test "passes along the given recipient" do
        staff = create(:staff_admin_user)
        travel_to("2021-09-24") do
          SponsorsPrimerMailer.expects(:payouts_export).once.with(
            sponsorable: @sponsorable,
            filename: "sponsors-#{@sponsorable}-payouts-2021-09-24.csv",
            export_content: SponsorsListing::PayoutsExport::CSV_HEADERS.join(",") + "\n",
            actor: staff,
            recipient: staff,
          ).returns(stub(deliver_later: nil))

          Failbot.expects(:report).never

          ExportSponsorsPayoutsJob.perform_now(
            @sponsorable,
            payout_id: "payout_id",
            actor: staff,
            recipient: staff,
          )
        end
      end

      test "calls the payouts export model with the correct parameters" do
        actor = @sponsorable.admins.first
        SponsorsPrimerMailer
          .expects(:payouts_export)
          .once
          .returns(stub(deliver_later: nil))

        SponsorsListing::PayoutsExport
          .expects(:new)
          .with(
            sponsors_listing: @org_listing,
            payout_id: "payout_id",
            stripe_account: nil,
          )
          .returns(stub(
            filename: "payouts_export_stub.csv",
            as_csv: "",
            "valid?": true,
          ))

        Failbot
          .expects(:report)
          .never

        ExportSponsorsPayoutsJob.perform_now(
          @sponsorable,
          actor: actor,
          payout_id: "payout_id",
        )
      end

      test "reports to Failbot if export is invalid" do
        SponsorsPrimerMailer
          .expects(:payouts_export)
          .never

        Failbot
          .expects(:report)
          .once

        ExportSponsorsPayoutsJob.perform_now(
          @sponsorable,
          payout_id: nil,
        )
      end

      test "sends mail" do
        assert_difference(-> { ActionMailer::Base.deliveries.count }) do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            ExportSponsorsPayoutsJob.perform_now @sponsorable, payout_id: "payout_id"
          end
        end
      end
    end
  end
end
