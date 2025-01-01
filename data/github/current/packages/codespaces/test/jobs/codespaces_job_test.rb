# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesJobTest < GitHub::TestCase
  class Job < CodespacesJob
    def perform(test_arg: nil)
      # Job just returns the current value of the global client timeouts
      Codespaces::Client.timeouts
    end
  end

  if GitHub.enterprise?
    test "doesn't enqueue when billing is disabled" do
      assert_no_enqueued_jobs do
        Job.perform_now
      end
    end
  else
    test "jobs don't enqueue if codespaces are not enabled" do
      GitHub.stubs(:codespaces_enabled?).returns(false)
      assert_no_enqueued_jobs do
        Job.perform_later
      end
    end

    test "it sets the default timeout for client API calls" do
      # Ensure that the global value of the client timeouts in the perform method
      # is what we expect it to be.
      assert_equal CodespacesJob::CLIENT_TIMEOUTS, Job.perform_now
    end

    context "perform_after_waiting_period" do
      test "sets the scheduled time correctly" do
        job = Job.perform_after_waiting_period(waiting_period: 30.days, test_arg: "test")
        assert_operator job.scheduled_at, :>, Time.now + 29.days
        assert_operator job.scheduled_at, :<, Time.now + 31.days
      end

      test "sets the method args correctly" do
        arguments = { test_arg: "test" }
        job = Job.perform_after_waiting_period(waiting_period: 30.days, **arguments)
        assert_equal job.arguments.count, 1
        assert_equal job.arguments[0], arguments
      end
    end

    context "stats_tags" do
      test "returns an empty array if no codespace or vscs_target is provided" do
        arguments = { test_arg: "test" }
        job = Job.new(**arguments)
        assert_equal job.stats_tags, []
      end

      test "returns an array of tags for the codespace as kwarg argument" do
        codespace = build(:codespace, :unprovisioned, vscs_target: "ppe")
        arguments = { test_arg: "test", codespace: codespace }

        job = Job.new(**arguments)

        tags = job.stats_tags
        refute_empty tags
        assert_includes tags, "codespaces_automated_testing:true"
      end

      test "returns an array of tags for the codespace as a first arg argument" do
        codespace = build(:codespace, :unprovisioned, vscs_target: "ppe")
        job = Job.new(codespace)

        tags = job.stats_tags
        refute_empty tags
        assert_includes tags, "codespaces_automated_testing:true"
      end

      test "returns an array of tags for the vscs_target as a kwarg argument" do
        arguments = { test_arg: "test", vscs_target: "ppe" }

        job = Job.new(**arguments)

        tags = job.stats_tags
        refute_empty tags
        assert_includes tags, "codespaces_automated_testing:true"
        assert_includes tags, "vscs_target:ppe"
      end
    end
  end
end
