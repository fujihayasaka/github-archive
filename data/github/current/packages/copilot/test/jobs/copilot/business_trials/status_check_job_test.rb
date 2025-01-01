# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BusinessTrials::StatusCheckJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @trial = create(:copilot_business_trial, :organization, state: "pending", ends_at: 20.days.from_now)
  end

  setup do
    enable_feature_flag(:copilot_business_trial_job)
  end

  context "perform" do
    test "it will do nothing if flag is disabled" do
      disable_feature_flag(:copilot_business_trial_job)
      logs = capture_logs do
        Copilot::BusinessTrials::StatusCheckJob.perform_now
      end
      assert_match "Skipping Copilot::BusinessTrials::StatusCheckJob", logs
    end

    context "when the trial is active" do
      test "updates to half_over at the 15 day mark" do
        freeze_time do
          @trial.update(state: "recently_started", ends_at: 15.days.from_now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.half_over?
          assert_match "Setting trial to half_over", logs
          assert_log_match logs, "gh.copilot.business_trial.id", @trial.id
        end
      end

      test "updates to nearly_over at the 5 day mark" do
        freeze_time do
          @trial.update(state: "half_over", ends_at: 5.days.from_now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.nearly_over?
          assert_match "Setting trial to nearly_over", logs
          assert_log_match logs, "gh.copilot.business_trial.id", @trial.id
        end
      end

      test "updates to final_day at the 1 day mark" do
        freeze_time do
          @trial.update(state: "nearly_over", ends_at: 1.day.from_now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.final_day?
          assert_match "Setting trial to final_day", logs
          assert_log_match logs, "gh.copilot.business_trial.id", @trial.id
        end
      end

      test "updates to expired at the ends_at time" do
        freeze_time do
          @trial.update(state: "final_day", ends_at: Time.now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.expired?
          assert_match "Setting trial to expired", logs
          assert_log_match logs, "gh.copilot.business_trial.id", @trial.id
        end
      end
    end

    context "when the trial is already in the proper state" do
      test "does not attempt to update to half_over" do
        freeze_time do
          @trial.update(state: "half_over", ends_at: 15.days.from_now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.half_over?
          refute_match "Setting trial to half_over", logs
        end
      end

      test "does not attempt to update to nearly_over" do
        freeze_time do
          @trial.update(state: "nearly_over", ends_at: 5.days.from_now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.nearly_over?
          refute_match "Setting trial to nearly_over", logs
        end
      end

      test "does not attempt to update to final_day" do
        freeze_time do
        end
        @trial.update(state: "final_day", ends_at: 1.day.from_now)

        logs = capture_logs do
          Copilot::BusinessTrials::StatusCheckJob.perform_now
        end

        assert @trial.reload.final_day?
        refute_match "Setting trial to final_day", logs
      end

      test "does not attempt to update to expired" do
        freeze_time do
          @trial.update(state: "expired", ends_at: Time.now)

          logs = capture_logs do
            Copilot::BusinessTrials::StatusCheckJob.perform_now
          end

          assert @trial.reload.expired?
          refute_match "Setting trial to expired", logs
        end
      end
    end

    context "when the trial is pending" do
      test "does not update the trial" do
        freeze_time do
          @trial.update(state: "pending", ends_at: 1.day.from_now)

          Copilot::BusinessTrials::StatusCheckJob.perform_now

          assert @trial.reload.pending?
        end
      end
    end

    context "when the trial is expired" do
      test "does not update the trial" do
        freeze_time do
          @trial.update(state: "expired", ends_at: 1.day.from_now)

          Copilot::BusinessTrials::StatusCheckJob.perform_now

          assert @trial.reload.expired?
        end
      end
    end

    context "when the trial is upgraded" do
      test "does not update the trial" do
        freeze_time do
          @trial.update(state: "upgraded", ends_at: 1.day.from_now)

          Copilot::BusinessTrials::StatusCheckJob.perform_now

          assert @trial.reload.upgraded?
        end
      end
    end
  end
end if GitHub.copilot_enabled?
