# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesDeleteJobTest < GitHub::TestCase

  test "skips vscs call if retry attempts are exhausted", skip_enterprise: true do
    codespace = create :codespace

    Codespaces::DeleteBase.expects(:call).with(codespace, reason: "user_requested", skip_vscs: false).times(3).raises(Codespaces::Error)
    Codespaces::DeleteBase.expects(:call).with(codespace, reason: "user_requested", skip_vscs: true).once

    assert_nothing_raised do
      perform_enqueued_jobs(only: [CodespacesDeleteJob]) do
        CodespacesDeleteJob.perform_now(codespace: codespace)
      end
    end
  end

  test "calls soft delete command when soft deletable" do
    codespace = create :codespace
    codespace.expects(:soft_deletable?).returns(true)
    Codespaces::SoftDelete.expects(:call).with(codespace, reason: "user_requested", skip_vscs: false)
    CodespacesDeleteJob.perform_now(codespace: codespace)
  end

  test "calls hard delete command when not soft deletable" do
    codespace = create :codespace
    codespace.expects(:soft_deletable?).returns(false)
    Codespaces::HardDelete.expects(:call).with(codespace, reason: "user_requested", skip_vscs: false)
    CodespacesDeleteJob.perform_now(codespace: codespace)
  end

  test "job retries on vscs api error" do
    Codespaces::VscsClient.any_instance.expects(:delete_environment).raises(Codespaces::VscsClient::TimeoutError)
    CodespacesDeleteJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [CodespacesDeleteJob]) do
        CodespacesDeleteJob.perform_now(codespace: create(:codespace, state: :deprovisioning))
      end
    end
  end
end
