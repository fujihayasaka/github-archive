# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesCleanupUnprocessedBillingMessagesJobTest < GitHub::TestCase
  include JobTestHelper

  test "only deletes records older than 90 days" do
    message_delete = create :codespace_unprocessed_billing_message,
        created_at: 91.days.ago
    message = create :codespace_unprocessed_billing_message,
        created_at: 89.days.ago
    assert_equal Codespaces::UnprocessedBillingMessage.count, 2
    CodespacesCleanupUnprocessedBillingMessagesJob.perform_now
    assert_equal Codespaces::UnprocessedBillingMessage.count, 1
    assert_equal Codespaces::UnprocessedBillingMessage.first, message
    assert_raises ActiveRecord::RecordNotFound do
      Codespaces::UnprocessedBillingMessage.find(message_delete.id)
    end
  end

  test "Deletes 1000 record then enqueues another job to continue" do
    create_list :codespace_unprocessed_billing_message, 1002, created_at: 91.days.ago
    CodespacesCleanupUnprocessedBillingMessagesJob.perform_now
    assert_equal Codespaces::UnprocessedBillingMessage.count, 2
    assert_enqueued_jobs 1, only: CodespacesCleanupUnprocessedBillingMessagesJob
  end

  test "runs hourly" do
    assert_equal  CodespacesCleanupUnprocessedBillingMessagesJob.schedule_options[:interval], 1.hour
  end
end unless GitHub.enterprise?
