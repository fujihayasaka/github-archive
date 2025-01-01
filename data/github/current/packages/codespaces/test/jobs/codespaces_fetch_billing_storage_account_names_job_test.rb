# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesFetchBillingStorageAccountNamesJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  setup do
    # Ensure these flags are off normally.
    GitHub.flipper[:codespaces_disable_billing_jobs].disable
    GitHub.flipper[:codespaces_disable_billing_jobs_ppe].disable
    GitHub.flipper[:codespaces_disable_billing_jobs_dev].disable

    FakeVSOServer.reset!
    @job_map = {
      ppe: CodespacesFetchBillingStorageAccountNamesPpeJob,
      production: CodespacesFetchBillingStorageAccountNamesJob,
      development: CodespacesFetchBillingStorageAccountNamesDevJob,
    }
  end

  test "development job can be disabled with the `codespaces_disable_billing_jobs_dev` flag" do
    GitHub.flipper[:codespaces_disable_billing_jobs_dev].enable

    assert_performed_jobs 0 do
      CodespacesFetchBillingStorageAccountNamesDevJob.perform_now
    end
  end

  test "ppe job can be disabled with the `codespaces_disable_billing_jobs_ppe` flag" do
    GitHub.flipper[:codespaces_disable_billing_jobs_ppe].enable

    assert_performed_jobs 0 do
      CodespacesFetchBillingStorageAccountNamesPpeJob.perform_now
    end
  end

  [:ppe, :development, :production].each do |vscs_target|
    test "it calls fetch billing messages job for each azure storage account name for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient
        .expects(:fetch_storage_accounts_and_tokens)
        .returns({ "sa1" => "key", "sa2" => "key" })
        .times(3)

      CodespacesFetchBillingMessagesJob.expects(:perform_later).with(azure_storage_account_name: "sa1", sequence_number: 1, environment: vscs_target)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).with(azure_storage_account_name: "sa2", sequence_number: 1, environment: vscs_target)

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end
    end

    test "it calls fetch billing messages job for each azure storage account name for #{vscs_target} and processes queues seperately" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient
        .expects(:fetch_storage_accounts_and_tokens)
        .with(vscs_target: vscs_target)
        .returns({ "sa1" => "key", "sa2" => "key" })
        .times(3)

      CodespacesFetchBillingMessagesJob.expects(:perform_later).with(azure_storage_account_name: "sa1", sequence_number: 1, environment: vscs_target)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).with(azure_storage_account_name: "sa2", sequence_number: 1, environment: vscs_target)

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end

      assert_equal 1, GitHub.dogstats.distributions("codespaces/billing/fetch_storage_account_names.success", tags: ["vscs_target:#{vscs_target}", "account_name:sa1"]).length
      assert_equal 1, GitHub.dogstats.distributions("codespaces/billing/fetch_storage_account_names.success", tags: ["vscs_target:#{vscs_target}", "account_name:sa2"]).length
    end

    test "scheduled to run every 10 minutes for #{vscs_target}", skip_enterprise: true do
      billing_job_class = @job_map[vscs_target]

      assert_equal billing_job_class.schedule_options[:interval], 10.minutes
    end

    test "can be disabled with the `codespaces_disable_billing_jobs` flag for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      GitHub.flipper[:codespaces_disable_billing_jobs].enable

      assert_performed_jobs 0 do
        billing_job_class.perform_now
      end
    end

    test "retries on a dirty exit for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      assert_retry_on_dirty_exit job: billing_job_class
    end

    test "job retries on Codespaces::Client::Error for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).raises(Codespaces::Client::TimeoutError)

      billing_job_class.any_instance.expects(:retry_job)

      assert_nothing_raised do
        perform_enqueued_jobs(only: [billing_job_class]) do
          billing_job_class.perform_later
        end
      end
    end

    test "if any of the storage account message count returns a bad response error we are rescued for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient.any_instance.expects(:fetch_storage_accounts_and_tokens).returns({ "sa1" => "key" })
      Codespaces::StorageClient.any_instance.expects(:approximate_messages_count).raises(Codespaces::Client::BadResponseError.new("bad response"))

      assert_nothing_raised do
        perform_enqueued_jobs(only: [billing_job_class, CodespacesFetchBillingStorageAccountJob]) do
          billing_job_class.perform_later
        end
      end
    end

    test "if any of the storage account message count returns a connection error we are rescued for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient.any_instance.expects(:fetch_storage_accounts_and_tokens).returns({ "sa1" => "key" })
      Codespaces::StorageClient.any_instance.expects(:approximate_messages_count).raises(Codespaces::StorageClient::ConnectionFailed.new)

      assert_nothing_raised do
        perform_enqueued_jobs(only: [billing_job_class, CodespacesFetchBillingStorageAccountJob]) do
          billing_job_class.perform_later
        end
      end
    end

    test "enqueues a minimum of one worker when there are less than a full worker's worth of estimated messages detected for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ "sa1" => "key" })
      Codespaces::StorageClient
        .any_instance
        .expects(:approximate_messages_count)
        .returns(10)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).once

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end
    end

    test "sends approximate_message_count to datadog for #{vscs_target}" do
      billing_job_class = @job_map[vscs_target]
      account_name = "sa1"
      mock_num_messages = 30

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ account_name => "key" })
      Codespaces::StorageClient
        .any_instance
        .expects(:approximate_messages_count)
        .returns(mock_num_messages)

      CodespacesFetchBillingMessagesJob.expects(:perform_later).with(
        azure_storage_account_name: "sa1",
        sequence_number: 1,
        environment: vscs_target
      )

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end

      assert_dogstats_gauge_value(mock_num_messages, "codespaces.fetch_billing_storage_account_names.approximate_messages_count", tags: ["account_name:#{account_name}", "vscs_target:#{vscs_target}"])
    end

    test "respect number of jobs to enqueue for #{vscs_target}" do
      GitHub.flipper[:codespaces_use_billing_worker_dial].enable

      billing_job_class = @job_map[vscs_target]
      account_name = "sa1"

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ account_name => "key" })
      Codespaces::StorageClient
        .any_instance
        .expects(:approximate_messages_count)
        .returns(40000000)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).times(Codespaces::Dials::BillingWorkerCount.new.value)

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end
    end

    test "respect number of jobs to enqueue with updated dial for #{vscs_target}" do
      GitHub.flipper[:codespaces_use_billing_worker_dial].enable
      new_dial_value = 120
      dial = Codespaces::Dials::BillingWorkerCount.new
      dial.value = new_dial_value
      dial.save
      billing_job_class = @job_map[vscs_target]

      account_name = "sa1"

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ account_name => "key" })
      Codespaces::StorageClient
        .any_instance
        .expects(:approximate_messages_count)
        .returns(40000000)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).times(new_dial_value)

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end
    end

    test "respect number of jobs to enqueue with flag off for #{vscs_target}" do
      GitHub.flipper[:codespaces_use_billing_worker_dial].disable

      billing_job_class = @job_map[vscs_target]
      account_name = "sa1"

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ account_name => "key" })
      Codespaces::StorageClient
        .any_instance
        .expects(:approximate_messages_count)
        .returns(40000000)
      CodespacesFetchBillingMessagesJob.expects(:perform_later).times(Codespaces::Dials::BillingWorkerCount.new.value)

      perform_enqueued_jobs(only: [CodespacesFetchBillingStorageAccountJob]) do
        billing_job_class.perform_now
      end
    end

  end
end unless GitHub.enterprise?
