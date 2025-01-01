# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BatchUpdateOrgSettingsJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "perform" do
    test "it can perform out of order" do
      business = create(:business)
      org = create(:organization, business: business)
      Copilot::Business.new(business)
      copilot_org = Copilot::Organization.new(org)
      configuration = create(:copilot_configuration, :business, configurable: business)

      Copilot::Organization.any_instance.expects(:cli_enabled!).with(false).never

      configuration.cli_enabled!
      # queue up a job but don't run it
      Copilot::BatchUpdateOrgSettingsJob.perform_later(business.id, :cli)

      Copilot::Organization.any_instance.expects(:cli_disabled!).with(false).once
      configuration.cli_disabled!
      # run second job that is out of order
      perform_enqueued_jobs(only: Copilot::BatchUpdateOrgSettingsJob) do
        # won't run because the first job is still in the queue
        Copilot::BatchUpdateOrgSettingsJob.perform_later(business.id, :a_chat)
      end
      Copilot::Organization.any_instance.expects(:cli_disabled!).with(true).once
      # Run original job, which should not switch org to cli_enabled because it was changed after job enqueued
      perform_enqueued_jobs(only: Copilot::BatchUpdateOrgSettingsJob)
      assert(copilot_org.cli_disabled?)
    end
  end
end if GitHub.copilot_enabled?
