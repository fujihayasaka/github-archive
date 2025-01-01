# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorshipsJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    fixtures do
      @sponsorable = create(:user, :sponsorable)
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: ExportSponsorshipsJob, args: [@sponsorable, {
        year: 2020, month: :March, format: :json, timeframe: "month"
      }]
    end

    context "#perform" do
      test "calls the SponsorsPrimerMailer with the export data" do
        SponsorsPrimerMailer
          .expects(:sponsorships_export)
          .once
          .with(sponsorable: @sponsorable, description: "March 2020",
            filename: "#{@sponsorable}-sponsorships-March-2020.json", mime_type: "application/json",
            export_content: "[]", actor: @sponsorable)
          .returns(stub(deliver_later: nil))

        Failbot
          .expects(:report)
          .never

        ExportSponsorshipsJob.perform_now(
          @sponsorable,
          year: 2020,
          month: :March,
          format: :json,
          timeframe: "month",
          actor: @sponsorable,
        )
      end

      test "instruments SponsorshipTransactionsExport hydro event if export is valid" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ExportSponsorshipsJob.perform_now @sponsorable,
            year: 2020, month: :march, format: :json, timeframe: "month",
            actor: @sponsorable

          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable.sponsors_listing),
            actor: Hydro::EntitySerializer.user(@sponsorable),
            sponsorable: Hydro::EntitySerializer.user(@sponsorable),
          }, schema: "github.sponsors.v1.SponsorshipTransactionsExport")
        end
      end

      test "instruments SponsorshipTransactionsExport hydro event with include sales tax info checked" do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          ExportSponsorshipsJob.perform_now @sponsorable,
            year: 2020, month: :march, format: :json, timeframe: "month",
            actor: @sponsorable

          assert_hydro_published({
            request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
            listing: Hydro::EntitySerializer.sponsors_listing(@sponsorable.sponsors_listing),
            actor: Hydro::EntitySerializer.user(@sponsorable),
            sponsorable: Hydro::EntitySerializer.user(@sponsorable),
          }, schema: "github.sponsors.v1.SponsorshipTransactionsExport")
        end
      end

      test "doesn't instrument SponsorshipTransactionsExport hydro event if export is invalid" do
        SponsorsPrimerMailer.expects(:sponsorships_export).never
        Failbot.expects(:report).once

        ExportSponsorshipsJob.perform_now @sponsorable,
          year: 2020, month: :invalid, format: :json, timeframe: "month",
          actor: @sponsorable

        refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipTransactionsExport")
      end

      test "reports to Failbot if export is invalid" do
        SponsorsPrimerMailer
          .expects(:sponsorships_export)
          .never

        Failbot
          .expects(:report)
          .once

        ExportSponsorshipsJob.perform_now(
          @sponsorable,
          year: 2020,
          month: :Invalid,
          format: :json,
          timeframe: "month",
          actor: @sponsorable,
        )
      end

      test "sends mail" do
        assert_difference(-> { ActionMailer::Base.deliveries.count }) do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            ExportSponsorshipsJob.perform_now @sponsorable,
              year: 2020, month: :March, format: :json, timeframe: "month",
              actor: @sponsorable
          end
        end
      end
    end
  end
end
