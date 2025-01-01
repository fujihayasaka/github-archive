# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::OrganizationAuthAndCaptureJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @organization = create(:organization)
  end

  setup do
    GitHub.flipper[:copilot_org_auth_and_capture_job].enable
  end

  context "perform" do
    test "doesn't call subjob with flag disabled" do
      GitHub.flipper[:copilot_org_auth_and_capture_job].disable

      logs = capture_logs do
        Copilot::Billing::OrganizationAuthAndCaptureJob.perform_now(@organization.id)
      end
      assert_match "Skipping Copilot::Billing::OrganizationAuthAndCaptureJob", logs
    end

    test "runs job" do
      logs = capture_logs do
        Copilot::Billing::OrganizationAuthAndCaptureJob.perform_now(@organization.id)
      end
      assert_match "Starting Copilot auth and capture job", logs
      assert_match "Skipping auth and capture, not eligible", logs
    end
  end
end if GitHub.copilot_enabled?
