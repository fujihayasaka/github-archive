# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CheckForShutdownCodespacesJobTest < GitHub::TestCase
  test "it updates the shutdown_at for codespaces with nil shutdown_at and a last_used_at far enough in the past" do
    codespace = create(:codespace, last_used_at: 3.days.ago, shutdown_at: nil)
    Codespaces::CheckForShutdownCodespacesJob.perform_now
    refute_nil codespace.reload.shutdown_at
  end

  test "it doesn't update the shutdown_at for codespaces with an existing shutdown_at and a last_used_at far enough in the past" do
    codespace = create(:codespace, last_used_at: 3.days.ago, shutdown_at: 2.days.ago)
    original_shutdown_time = codespace.shutdown_at
    Codespaces::CheckForShutdownCodespacesJob.perform_now
    assert_equal codespace.reload.shutdown_at, original_shutdown_time
  end

  test "it doesn't update the shutdown_at for codespaces with nil shutdown_at and a last_used_at that's too recent" do
    codespace = create(:codespace, last_used_at: 1.day.ago, shutdown_at: nil)
    Codespaces::CheckForShutdownCodespacesJob.perform_now
    assert_nil codespace.reload.shutdown_at
  end

  test "it ignores codespaces that were not provisioned when the feature is enabled" do
    enable_feature_flag(:codespaces_clean_up_stuck_provisioning)
    codespace = create(:codespace, :unprovisioned, last_used_at: 3.days.ago, shutdown_at: nil)
    Codespaces::CheckForShutdownCodespacesJob.perform_now
    assert_nil codespace.reload.shutdown_at
  end

  test "it skips exporting codespaces when the feature is enabled" do
    enable_feature_flag(:codespaces_clean_up_stuck_provisioning)
    freeze_time do
      codespace = create(:codespace, last_used_at: 3.days.ago, shutdown_at: nil, last_export_start_at: 10.seconds.ago, last_export_end_at: nil)
      Codespaces::CheckForShutdownCodespacesJob.perform_now
      assert_nil codespace.reload.shutdown_at
    end
  end
end
