# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorsSponsorshipsJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    fixtures do
      @sponsor = create(:organization)
      @user = create(:user)
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: ExportSponsorsSponsorshipsJob, args: [@sponsor, {
        active: true, actor: @sponsor
      }]
    end

    context "#perform" do
      test "calls the SponsorsPrimerMailer with the export data" do
        travel_to(Date.parse("2024-01-01")) do
          expected_content = Sponsors::SponsorshipsExport.new(sponsor: @sponsor, active: true).csv
          SponsorsPrimerMailer
            .expects(:sponsors_sponsorships_export)
            .once
            .with(
              sponsor: @sponsor,
              filename: "#{@sponsor}-sponsorships-#{DateTime.current}.csv",
              mime_type: "text/csv",
              export_content: expected_content,
              actor: @user,
            ).returns(stub(deliver_later: nil))

          ExportSponsorsSponsorshipsJob.perform_now(
            @sponsor,
            active: true,
            actor: @user,
          )
        end
      end

      test "sends mail" do
        assert_difference(-> { ActionMailer::Base.deliveries.count }) do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            ExportSponsorsSponsorshipsJob.perform_now(
              @sponsor,
              active: true,
              actor: @user,
            )
          end
        end
      end
    end
  end
end
