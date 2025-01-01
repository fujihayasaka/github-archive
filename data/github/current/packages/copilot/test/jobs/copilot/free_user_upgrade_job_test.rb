# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
class Copilot::FreeUserUpgradeJobTest < GitHub::TestCase
  include CopilotTestHelper

  context "perform" do
    test "does nothing when feature flag is disabled" do
      disable_feature_flag(:free_user_upgrade_job)
      disable_feature_flag(:free_user_upgrade_job_noop)
      create(:copilot_limited_user)

      logs = capture_logs do
        Copilot::FreeUserUpgradeJob.perform_now
      end

      refute_includes logs, "Starting FreeUserUpgradeJob"
      refute_includes logs, "Queueing FreeUserUpgradeBatchJob for batch of Copilot Free users"
    end

    test "calls FreeUserUpgradeJob in batches" do
      enable_feature_flag(:free_user_upgrade_job)
      batch_size_override = 2

      stub_const(Copilot::FreeUserUpgradeJob, :BATCH_SIZE, batch_size_override) do
        (batch_size_override + 1).times.map do
          create(:copilot_limited_user)
        end

        logs = capture_logs do
          Copilot::FreeUserUpgradeJob.perform_now
        end

        assert_includes logs, "Starting FreeUserUpgradeJob"
        queue_count = logs.scan("Queueing FreeUserUpgradeBatchJob for batch of Copilot Free users").count
        assert_equal 2, queue_count
      end
    end

    test "processes multiple limited users" do
      enable_feature_flag(:free_user_upgrade_job)
      limited_users_count = 3
      limited_users = limited_users_count.times.map do
        create(:copilot_limited_user)
      end

      expected_first_id = limited_users.first.id
      expected_last_id = limited_users.last.id

      logs = capture_logs do
        Copilot::FreeUserUpgradeJob.perform_now
      end

      assert_includes logs, "gh.copilot.batch_size=\"3\""
      assert_includes logs, "gh.copilot.batch_first_seat_id=\"#{expected_first_id}\""
      assert_includes logs, "gh.copilot.batch_last_seat_id=\"#{expected_last_id}\""
    end
  end
end
