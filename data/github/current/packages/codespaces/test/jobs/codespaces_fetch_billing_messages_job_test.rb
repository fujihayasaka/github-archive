# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesFetchBillingMessagesJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    disable_feature_flag(:codespaces_disable_billing_jobs)
  end

  fixtures do
    @azure_storage_account_name = SecureRandom.uuid
    @other_azure_storage_account_name = SecureRandom.uuid
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: CodespacesFetchBillingMessagesJob
  end

  test "has a lock" do
    job1 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @azure_storage_account_name)
    job2 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @azure_storage_account_name)
    job3 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @other_azure_storage_account_name)

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "locks on storage account name/sequence number" do
    job1 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @azure_storage_account_name, sequence_number: 1)
    job2 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @azure_storage_account_name, sequence_number: 1)
    job3 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @azure_storage_account_name, sequence_number: 2)
    job4 = CodespacesFetchBillingMessagesJob.new(azure_storage_account_name: @other_azure_storage_account_name, sequence_number: 1)

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
    refute_equal job1.lock_key, job4.lock_key
  end

  test "it calls Codespaces::Billing::FetchMessages" do
    Codespaces::Billing::FetchMessages.expects(:call).with(azure_storage_account_name: @azure_storage_account_name, environment: :production)
    CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name)
  end

  test "can be disabled with the `disable_codespace_billing_fan_out` flag" do
    enable_feature_flag(:codespaces_disable_billing_jobs)

    Codespaces::Billing::FetchMessages.expects(:call).never
    CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name)
  end

  test "it enqueues another CodespacesFetchBillingMessagesJob if there are more messages in the queue" do
    Codespaces::Billing::FetchMessages
      .expects(:call)
      .with(azure_storage_account_name: @azure_storage_account_name, environment: :production)
      .returns(true)

    assert_enqueued_jobs 1, only: CodespacesFetchBillingMessagesJob do
      CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name)
    end
  end

  test "it carries its sequence_number forward to the next enqueued job" do
    Codespaces::Billing::FetchMessages
      .expects(:call)
      .with(azure_storage_account_name: @azure_storage_account_name, environment: :production)
      .returns(true)

    CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name, sequence_number: 11)

    assert_enqueued_jobs 1, only: CodespacesFetchBillingMessagesJob
    # this one goes to 11
    assert_enqueued_with job: CodespacesFetchBillingMessagesJob, args: [{ azure_storage_account_name: @azure_storage_account_name, environment: :production, sequence_number: 11 }]
  end

  test "it clears the lock on this job/arguments" do
    Codespaces::Billing::FetchMessages
      .expects(:call)
      .with(azure_storage_account_name: @azure_storage_account_name, environment: :production)
      .returns(true)

    # both jobs will see more messages in the queue and try to clear the lock
    CodespacesFetchBillingMessagesJob.any_instance.expects(:clear_lock).twice

    assert_enqueued_jobs 1, only: CodespacesFetchBillingMessagesJob do
      CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name)
    end
  end

  test "doesn't enqueue a new job if there's nothing left in the queue" do
    Codespaces::Billing::FetchMessages
      .expects(:call)
      .with(azure_storage_account_name: @azure_storage_account_name, environment: :production)
      .returns(false)

    assert_enqueued_jobs 0 do
      CodespacesFetchBillingMessagesJob.perform_now(azure_storage_account_name: @azure_storage_account_name)
    end
  end
end unless GitHub.enterprise?
