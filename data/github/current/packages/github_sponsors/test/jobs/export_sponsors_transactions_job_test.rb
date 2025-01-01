# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorsTransactionsJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      @listing = create(:sponsors_listing, :fiscal_host)
      @sponsorable = @listing.sponsorable
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: ExportSponsorsTransactionsJob, args: [@sponsorable, {
        timeframe: "month"
      }]
    end

    context "#perform" do
      test "calls the SponsorsMailer with the export data" do
        travel_to("2021-03-29") do
          actor = create(:user)
          SponsorsPrimerMailer
            .expects(:sponsors_transactions_export)
            .once
            .with(
              sponsorable: @sponsorable,
              filename: "sponsors-#{@sponsorable}-transactions-2021-03-29.csv",
              mime_type: "text/csv",
              export_content: SponsorsListing::TransactionsExport::CSV_HEADERS.join(",") + "\n",
              description: "the last month",
              actor: actor,
              recipient: nil,
            )
            .returns(stub(deliver_later: nil))

          ExportSponsorsTransactionsJob.perform_now(@sponsorable, timeframe: "month", actor: actor)
        end
      end

      test "passes along recipient when specified" do
        staff = create(:staff_admin_user)

        SponsorsPrimerMailer.expects(:sponsors_transactions_export).once.with(
          sponsorable: @sponsorable,
          filename: "sponsors-#{@sponsorable}-transactions-all-time.csv",
          mime_type: "text/csv",
          export_content: SponsorsListing::TransactionsExport::CSV_HEADERS.join(",") + "\n",
          description: "all time",
          actor: staff,
          recipient: staff,
        ).returns(stub(deliver_later: nil))

        ExportSponsorsTransactionsJob.perform_now(@sponsorable, timeframe: "all", actor: staff, recipient: staff)
      end

      test "sends mail" do
        assert_difference(-> { ActionMailer::Base.deliveries.count }) do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            ExportSponsorsTransactionsJob.perform_now @sponsorable, timeframe: "month"
          end
        end
      end
    end
  end
end
