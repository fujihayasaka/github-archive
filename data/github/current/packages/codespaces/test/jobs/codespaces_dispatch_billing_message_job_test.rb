# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesDispatchBillingMessageJobTest < GitHub::TestCase
  include JobTestHelper

  test "has a lock" do
    job1 = CodespacesDispatchBillingMessageJob.new(message_body: { "testing": "hashes" }, vscs_target: "target", codespace_plan_id: "id")
    job2 = CodespacesDispatchBillingMessageJob.new(message_body: { "testing": "hashes" }, vscs_target: "target", codespace_plan_id: "id")
    job3 = CodespacesDispatchBillingMessageJob.new(message_body: { "testing": "hashes changed" }, vscs_target: "target", codespace_plan_id: "id")

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "it calls Codespaces::Billing::DispatchMessage" do
    Codespaces::Billing::DispatchMessage.expects(:call).with(message: { some_message: "test" }.to_json, message_body: "body", vscs_target: "target", codespace_plan_id: "id")
    CodespacesDispatchBillingMessageJob.perform_now(message: { some_message: "test" }.to_json, message_body: "body", vscs_target: "target", codespace_plan_id: "id")
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: CodespacesDispatchBillingMessageJob
  end
end unless GitHub.enterprise?
