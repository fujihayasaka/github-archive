# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorsDependenciesJobTest < GitHub::TestCase
  include JobTestHelper
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    fixtures do
      @org = create(:organization)
      @sponsorables = [create(:user), create(:organization)]
      @viewer = create(:user)
    end

    setup do
      GitHub.flipper[:sponsors_org_dependencies].enable(@org)
    end

    test "retry conditions" do
      assert_retry_on_dirty_exit job: ExportSponsorsDependenciesJob, args: [@sponsor, {
        org: @org, actor: @sponsor
      }]
    end

    context "#perform" do
      test "does not call the export method if sponsors_org_dependencies FF is disabled" do
        GitHub.flipper[:sponsors_org_dependencies].disable(@org)

        SponsorsPrimerMailer.expects(:sponsors_dependencies_export).never

        ExportSponsorsDependenciesJob.perform_later(
          org: @org,
          actor: @viewer,
        )
      end

      test "calls the SponsorsPrimerMailer with the export data" do
        travel_to(Date.parse("2024-01-01")) do
          expected_content = Sponsors::SponsorshipsDependenciesExport.new(org: @org, viewer: @viewer).csv
          SponsorsPrimerMailer
            .expects(:sponsors_dependencies_export)
            .once
            .with(
              filename: "#{@org}-dependencies-#{DateTime.current}.csv",
              mime_type: "text/csv",
              export_content: expected_content,
              actor: @viewer,
            ).returns(stub(deliver_now: nil))

          ExportSponsorsDependenciesJob.perform_now(
            org: @org,
            actor: @viewer,
          )
        end
      end

      test "sends mail" do
        assert_difference(-> { ActionMailer::Base.deliveries.count }) do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            ExportSponsorsDependenciesJob.perform_now(
              org: @org,
              actor: @viewer,
            )
          end
        end
      end
    end
  end
end
