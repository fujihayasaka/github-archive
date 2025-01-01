# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::FetchMessagesTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @plan = create(:codespace_plan, :existing)
    @codespaces = create_list(:codespace, 3, plan: @plan)
    @codespace_on_other_plan = create(:codespace, plan: create(:codespace_plan, location: "EastUs"))
  end

  setup do
    FakeVSOServer.reset!
    @queued_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces)
    @options = {
      azure_storage_account_name: "anything"
    }
  end

  test "makes call to dispatch message" do
    queue_message = @queued_message[:QueueMessage]
    message = Codespaces::StorageClient::Message.new(
      id: queue_message[:MessageId],
      pop_receipt: queue_message[:PopReceipt],
      body: queue_message[:MessageText].deep_stringify_keys,
      dequeue_count: 1,
      insertion_time: queue_message[:InsertionTime],
      expiration_time: queue_message[:ExpirationTime],
      time_next_visible: queue_message[:TimeNextVisible],
    )
    message_arg = GitHub.flipper[:codespaces_hide_message_in_billing].enabled? ? nil : message.to_json

    CodespacesDispatchBillingMessageJob.expects(:perform_later).with(message: message_arg, message_body: message.body, vscs_target: @codespaces.first.vscs_target, codespace_plan_id: @codespaces.first.plan.id)

    Codespaces::Billing::FetchMessages.new(**@options).call
  end

  test "raises alert with extra params" do
    message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, fields_to_add: { "extra" => "field" })

    id = message[:QueueMessage][:MessageId]
    Codespaces::ErrorReporter.any_instance.expects(:report).once.with(instance_of(Codespaces::Billing::FetchMessages::AdditionalParamsError), billing_message_id: id)

    Codespaces::Billing::FetchMessages.new(**@options).call
  end

  test "doesn't raise alert with sizeInKb" do
    storage = {
      "sku": "standardLinux",
      "sizeInKb": 1_000_000,
      "size": 64,
      "usage": 230400.0
    }

    message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, storage: storage)
    Codespaces::ErrorReporter.any_instance.expects(:report).never

    Codespaces::Billing::FetchMessages.new(**@options).call
  end

  test "it tracks error context for each fetched message" do
    FakeVSOServer.reset!
    msg1 = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces)
    msg2 = FakeVSOServer.add_billing_messages_for(plan: @codespace_on_other_plan.plan, codespaces: @codespace_on_other_plan)

    Failbot.stubs(:push)
    Failbot.expects(:push).
      with(equals(
        codespace_plan_name: @plan.name,
        codespace_azure_message_id: msg1[:QueueMessage][:MessageId],
        codespace_billing_message_id: msg1[:QueueMessage][:MessageText][:id]
      )).then.
      with(equals(
        codespace_plan_name: @codespace_on_other_plan.plan.name,
        codespace_azure_message_id: msg2[:QueueMessage][:MessageId],
        codespace_billing_message_id: msg2[:QueueMessage][:MessageText][:id]
      ))

    Codespaces::Billing::FetchMessages.new(**@options).call
  end

  context "when there are multiple messages for different plans" do

    test "it logs errors when a plan can't be found" do
      message_id = SecureRandom.uuid
      FakeVSOServer.add_billing_messages_for(plan: @codespace_on_other_plan.plan, codespaces: @codespace_on_other_plan, message_id: message_id)

      # Rename our plan so it does not match what we just set up
      plan_name = @codespace_on_other_plan.plan.name
      @codespace_on_other_plan.plan.update(name: SecureRandom.uuid)

      Codespaces::ErrorReporter.any_instance.expects(:report).once.with(instance_of(ActiveRecord::RecordNotFound))

      Codespaces::Billing::FetchMessages.new(**@options).call
    end

    test "it moves the deleted plan billing message to the dead letter queue" do
      FakeVSOServer.reset!
      codespace = create(:codespace)
      plan = codespace.plan

      msg = FakeVSOServer.add_billing_messages_for(plan: plan, codespaces: codespace)

      # Rename our plan so it does not match what we just set up
      plan.update(name: SecureRandom.uuid)
      Codespaces::Billing::FetchMessages.any_instance.expects(:ack_message).with(
        instance_of(Codespaces::StorageClient::Message)
      ).once

      Codespaces::ErrorReporter.any_instance.expects(:report).once.with(instance_of(ActiveRecord::RecordNotFound))

      assert_changes -> { Codespaces::UnprocessedBillingMessage.count }, from: 0, to: 1 do
        Codespaces::Billing::FetchMessages.new(**@options).call
      end

      dead_letter = Codespaces::UnprocessedBillingMessage.last
      assert_equal msg[:QueueMessage][:MessageId], T.must(dead_letter).message_id
      assert_equal "anything", T.must(dead_letter).azure_storage_account_name
      assert_equal msg[:QueueMessage][:MessageText].to_json, T.must(dead_letter).body
    end

    test "it does not move the message to the dlq or send error report for non-production" do
      FakeVSOServer.reset!

      msg = FakeVSOServer.add_billing_messages_for(plan: @codespace_on_other_plan.plan, codespaces: @codespace_on_other_plan)

      # Rename our plan so it does not match what we just set up
      @codespace_on_other_plan.plan.update(name: SecureRandom.uuid)
      Codespaces::Billing::FetchMessages.any_instance.expects(:ack_message).with(
        instance_of(Codespaces::StorageClient::Message)
      ).once

      @options[:environment] = :development
      create(:codespace_plan, vscs_target: @options[:environment])
      Codespaces::ErrorReporter.any_instance.expects(:report).never

      assert_no_changes -> { Codespaces::UnprocessedBillingMessage.count } do
        Codespaces::Billing::FetchMessages.new(**@options).call
      end
      # make sure it doesn't increment the count
      assert_dogstats_count_value(0, "codespaces.fetch_billing_messages.dead_letters", tags: ["account_name:anything", "vscs_target:development"])
    end
  end

  context "deleting consumed messages" do
    test "it batches deletions" do
      client = Codespaces::StorageClient.new(account_name: "anything")

      client.expects(:delete_messages).with do |parameters|
        assert parameters.length == 1
        message = parameters.first
        assert_equal @queued_message[:QueueMessage][:MessageId], message.id
        assert_equal @queued_message[:QueueMessage][:PopReceipt], message.pop_receipt
      end
      Codespaces::Billing::FetchMessages.new(**@options.merge(client: client)).call
    end
  end

  context "after processing messages we've received" do
    test "#call returns true if we query and see more messages on the queue" do
      messages_count = 1
      account_name = "anything"
      client = Codespaces::StorageClient.new(account_name: account_name)
      client.expects(:approximate_messages_count).returns(messages_count)
      assert Codespaces::Billing::FetchMessages.new(**@options.merge(client: client)).call
      assert_dogstats_gauge_value(messages_count, "codespaces.fetch_billing_messages.approximate_messages_count", tags: ["account_name:#{account_name}", "vscs_target:production"])
    end

    test "#call returns false if we query and see no messages on the queue" do
      messages_count = 0
      account_name = "anything"
      client = Codespaces::StorageClient.new(account_name: account_name)
      client.expects(:approximate_messages_count).returns(messages_count) # empty
      assert_enqueued_jobs 0, only: CodespacesFetchBillingMessagesJob

      refute Codespaces::Billing::FetchMessages.new(**@options.merge(client: client)).call
      assert_dogstats_gauge_value(messages_count, "codespaces.fetch_billing_messages.approximate_messages_count", tags: ["account_name:#{account_name}", "vscs_target:production"])
    end
  end

  context "invalid unprocessable messages" do
    test "are added to dead letter queue and deleted if dequeued too many times" do
      invalid_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, dequeue_count: 3, keys_to_delete: [:resourceUsage])
      client = Codespaces::StorageClient.new(account_name: "anything")
      Codespaces::Billing::FetchMessages.any_instance.expects(:ack_message).with(
        instance_of(Codespaces::StorageClient::Message)
      ).twice

      assert_changes -> { Codespaces::UnprocessedBillingMessage.count }, from: 0, to: 1 do
        Codespaces::Billing::FetchMessages.new(**@options.merge(client: client)).call
      end

      dead_letter = Codespaces::UnprocessedBillingMessage.last

      assert_equal invalid_message[:QueueMessage][:MessageId], T.must(dead_letter).message_id
      assert_equal "anything", T.must(dead_letter).azure_storage_account_name
      assert_equal invalid_message[:QueueMessage][:MessageText].to_json, T.must(dead_letter).body
    end

    test "are ignored if they haven't been dequeued enough times yet" do
      invalid_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, dequeue_count: 2, keys_to_delete: [:resourceUsage])
      client = Codespaces::StorageClient.new(account_name: "anything")
      client.stubs(:delete_message)
      client.expects(:delete_message).with(
        message_id: invalid_message[:QueueMessage][:MessageId],
        pop_receipt: invalid_message[:QueueMessage][:PopReceipt]
      ).never

      assert_no_changes -> { Codespaces::UnprocessedBillingMessage.count } do
        Codespaces::Billing::FetchMessages.new(**@options.merge(client: client)).call
      end
    end

    test "doesn't block valid messages from being consumed" do
      invalid_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, dequeue_count: 3, keys_to_delete: [:resourceUsage])
      second_valid_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces)

      Failbot.expects(:report).with do |error|
        error.is_a?(Codespaces::Error) && error.message.include?("Failed vscs_billing_schema validation")
      end

      assert_changes -> { Codespaces::UnprocessedBillingMessage.count }, from: 0, to: 1 do
        Codespaces::Billing::FetchMessages.new(**@options).call
      end
    end
  end

  context "fetch metrics" do
    test "are recorded when the command is called" do
      invalid_message = FakeVSOServer.add_billing_messages_for(plan: @plan, codespaces: @codespaces, dequeue_count: 3, keys_to_delete: [:resourceUsage])
      Codespaces::Billing::FetchMessages.new(**@options).call

      assert_dogstats_count_value(2, "codespaces.fetch_billing_messages.messages_fetched", tags: ["account_name:anything", "vscs_target:production"])
      assert_dogstats_count_value(1, "codespaces.fetch_billing_messages.dead_letters", tags: ["account_name:anything", "vscs_target:production"])
    end

    test "are recorded even if an exception occurs" do

      Codespaces::Billing::FetchMessages.any_instance.expects(:ack_message).raises(StandardError)

      assert_raises(StandardError) do
        Codespaces::Billing::FetchMessages.new(**@options).call
      end

      assert_dogstats_count_value(1, "codespaces.fetch_billing_messages.messages_fetched", tags: ["account_name:anything", "vscs_target:production"])
      assert_dogstats_count_value(0, "codespaces.fetch_billing_messages.dead_letters", tags: ["account_name:anything", "vscs_target:production"])
    end
  end
end
