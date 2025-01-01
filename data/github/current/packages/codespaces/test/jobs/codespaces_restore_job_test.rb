# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesRestoreJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "calls restore command" do
    codespace = create(:codespace, :deprovisioned, owner: @user, billable_owner: @user, deleted_at: Time.current)
    Codespaces::Restore.expects(:call).with(codespace)
    CodespacesRestoreJob.perform_now(codespace: codespace)
  end

  test "job retries on vscs api error" do
    codespace = create(:codespace, :deprovisioned, owner: @user, billable_owner: @user, deleted_at: Time.current)
    Codespaces::VscsClient.any_instance.expects(:restore_environment).raises(Codespaces::VscsClient::TimeoutError)
    CodespacesRestoreJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      perform_enqueued_jobs(only: [CodespacesRestoreJob]) do
        CodespacesRestoreJob.perform_now(codespace: codespace)
      end
    end
  end
end
