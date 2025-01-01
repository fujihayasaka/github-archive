# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesProcessSystemEventJobTest < GitHub::TestCase
  test "it calls the ProcessSystemEvent command with codespaces" do
    codespace_a = create(:codespace)
    codespace_b = create(:codespace)
    Codespaces::ProcessSystemEvent.expects(:call).with([codespace_a, codespace_b], transfer_billable_owner: true, deletion_reason: Codespace.deletion_reasons[:process_system_event])

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      CodespacesProcessSystemEventJob.perform_now(codespaces: [codespace_a, codespace_b])
    end
  end
end
