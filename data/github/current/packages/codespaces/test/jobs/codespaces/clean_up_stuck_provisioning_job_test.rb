# typed: true
# frozen_string_literal: true

require "test_helper"

class CleanUpStuckProvisioningJobTest < GitHub::TestCase
  test "it does nothing when disabled", skip_enterprise: true do
    disable_feature_flag(:codespaces_clean_up_stuck_provisioning)

    stuck = create(:codespace, :stuck_provisioning)
    perform_enqueued_jobs(only: [CodespacesDeleteJob]) do
      Codespaces::CleanUpStuckProvisioningJob.perform_now
    end
    assert_equal stuck, Codespace.find_by(id: stuck.id)
  end

  test "it finds and deletes codespaces that got stuck in provisioning when enabled", skip_enterprise: true do
    enable_feature_flag(:codespaces_clean_up_stuck_provisioning)

    stuck = create(:codespace, :stuck_provisioning)
    still_provisioning = create(:codespace, :provisioning)
    provisioned = create(:codespace)
    perform_enqueued_jobs(only: [CodespacesDeleteJob]) do
      Codespaces::CleanUpStuckProvisioningJob.perform_now
    end
    refute Codespace.find_by(id: stuck.id)
    assert Codespace.find_by(id: still_provisioning.id)
    assert Codespace.find_by(id: provisioned.id)
  end

  test "it fails any pending async operation when deleting a codespace" do
    enable_feature_flag(:codespaces_clean_up_stuck_provisioning)

    stuck = create(:codespace, :stuck_provisioning)
    operation = create(:codespaces_async_operation, :started, operation: :create_codespace, codespace: stuck)
    Codespaces::CleanUpStuckProvisioningJob.perform_now
    assert operation.reload.op_ended_at
  end

  test "it doesn't touch a completed operation even though that should not really happen" do
    enable_feature_flag(:codespaces_clean_up_stuck_provisioning)

    stuck = create(:codespace, :stuck_provisioning)
    operation = create(:codespaces_async_operation, :finished, operation: :create_codespace, codespace: stuck)
    original_ended_at = operation.op_ended_at
    assert original_ended_at
    Codespaces::CleanUpStuckProvisioningJob.perform_now
    assert_equal original_ended_at, operation.reload.op_ended_at
  end
end
