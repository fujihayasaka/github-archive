# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ExportSponsorableMaintainersJobTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include JobTestHelper

  fixtures do
    @viewer = create(:user, :verified)
  end

  setup do
    @filename = "some-export.csv"
    @export_content = Sponsors::ExploreExporter::HEADERS.join(",") + "\n"
    Sponsors::ExploreExporter.any_instance.stubs(:to_csv).returns(@export_content)
    Sponsors::ExploreExporter.any_instance.stubs(:filename).returns(@filename)
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: ExportSponsorableMaintainersJob, args: [{ viewer: @viewer }]
  end

  if GitHub.sponsors_enabled?
    test "no-op when viewer isn't given" do
      assert_no_emails do
        ExportSponsorableMaintainersJob.perform_now(viewer: nil)
      end
    end

    test "no-op when viewer doesn't have a verified email address" do
      user = create(:user)

      assert_no_emails do
        ExportSponsorableMaintainersJob.perform_now(viewer: user)
      end
    end

    test "no-op when viewer lacks permission with given org" do
      org = create(:organization)

      assert_no_emails do
        ExportSponsorableMaintainersJob.perform_now(viewer: @viewer, org: org)
      end
    end

    test "sends email to viewer" do
      SponsorsPrimerMailer.expects(:sponsorable_maintainers_export).with(
        recipient: @viewer,
        filename: @filename,
        mime_type: "text/csv",
        export_content: @export_content,
        org: nil,
        explore_params: {},
      ).once.returns(stub(deliver_now: nil))

      ExportSponsorableMaintainersJob.perform_now(viewer: @viewer)
    end

    test "sends email to viewer when there are filters applied" do
      ecosystems = %w[NPM RUBYGEMS]
      direct_only = false
      org = create(:organization, admin: @viewer)
      sort_by = "LEAST_USED"
      SponsorsPrimerMailer.expects(:sponsorable_maintainers_export).with(
        recipient: @viewer,
        filename: @filename,
        mime_type: "text/csv",
        export_content: @export_content,
        org: org,
        explore_params: { account: org.login, direct: "0", sort_by: sort_by, ecosystems: "NPM,RUBYGEMS" },
      ).once.returns(stub(deliver_now: nil))

      ExportSponsorableMaintainersJob.perform_now(viewer: @viewer, sort_by: sort_by, ecosystems: ecosystems,
        direct_only: direct_only, org: org)
    end
  else
    test "no-op when Sponsors isn't enabled" do
      assert_no_emails do
        ExportSponsorableMaintainersJob.perform_now(viewer: @viewer)
      end
    end
  end
end
