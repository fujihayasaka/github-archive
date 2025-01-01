# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityCenter
  class RepositoryReconciliationJobTest < GitHub::TestCase
    context "#perform" do
      test "queues job in reconciliation queue" do
        assert_enqueued_jobs(1, only: RepositoryReconciliationJob, queue: :security_center_reconciliation) do
          RepositoryReconciliationJob.perform_later(repository_id: 1, source_event: "security_center.test")
        end
      end

      test "performs the job" do
        perform_enqueued_jobs(only: RepositoryReconciliationJob) do
          RepositoryReconciliationJob.perform_later(repository_id: 1, source_event: "security_center.test")
        end
      end
    end
  end
end
