# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesStorageClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    plan = create :codespace_plan, :existing
    @codespace = create :codespace, plan: plan
    @account_name = "anything"
  end

  context "SAS Key Authentication" do
    test "SAS keys are fetched and memoized" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      client = Codespaces::StorageClient.new(account_name: @account_name, environment: :development)
      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ @account_name => "key" })

      client.get_messages

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).never
      client.get_messages
    end

    test "if no SAS key is found for account name, it raises" do
      client = Codespaces::StorageClient.new(account_name: "non-existent-account")
      assert_raises do
        client.get_messages
      end
    end

    test "SAS key is appended to query params" do
      FakeVSOServer.reset!

      client = Codespaces::StorageClient.new(account_name: @account_name)
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]

      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )

      client.delete_messages([good_message])

      req = FakeVSOServer.requests.find { |req| req.env["REQUEST_METHOD"] == "DELETE" }
      assert_equal queued_message[:PopReceipt], req.params["popreceipt"]
      assert_equal "test-sig", req.params["sig"]
    end

    test "SAS key is not logged by Faraday" do
      FakeVSOServer.reset!

      client = Codespaces::StorageClient.new(account_name: @account_name)

      output = capture_logs do
        client.get_messages
      end

      assert output.slice("sig=[REMOVED]")
      refute output.slice("sig=test-sig")
    end

    test "SAS key is not part of the logged request url in exceptions" do
      FakeVSOServer.reset!
      bad_message = Codespaces::StorageClient::Message.new(
        id: SecureRandom.uuid,
        pop_receipt: SecureRandom.uuid,
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: 1.minute.ago.iso8601,
        expiration_time: 1.minute.from_now.iso8601,
        time_next_visible: 2.minutes.from_now.iso8601,
      )

      err = Codespaces::StorageClient.new(account_name: @account_name).delete_messages([bad_message]).first
      assert err.is_a? Exception
      assert err.to_s.exclude? FakeVSOServer::TEST_SIG
    end

    test "parsing of existing query params supports + and doesn't raise 404" do
      FakeVSOServer.reset!
      message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace, pop_receipt: "a+bc=")

      client = Codespaces::StorageClient.new(account_name: @account_name)
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]

      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )

      response = client.delete_messages([good_message]).first
      refute response.is_a? Exception
    end
  end

  context "SAS Key Authentication with vscs" do
    test "SAS keys are fetched and memoized" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      client = Codespaces::StorageClient.new(account_name: @account_name, environment: :development)
      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).returns({ @account_name => "key" })
      client.get_messages

      Codespaces::VscsClient.expects(:fetch_storage_accounts_and_tokens).never
      client.get_messages
    end

    test "if no SAS key is found for account name, it raises" do
      client = Codespaces::StorageClient.new(account_name: "non-existent-account")
      assert_raises do
        client.get_messages
      end
    end

    test "SAS key is appended to query params" do
      FakeVSOServer.reset!

      client = Codespaces::StorageClient.new(account_name: @account_name)
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]

      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible]
      )

      client.delete_messages([good_message])

      req = FakeVSOServer.requests.find { |req| req.env["REQUEST_METHOD"] == "DELETE" }
      assert_equal queued_message[:PopReceipt], req.params["popreceipt"]
      assert_equal "test-sig", req.params["sig"]
    end

    test "SAS key is not logged by Faraday" do
      FakeVSOServer.reset!

      client = Codespaces::StorageClient.new(account_name: @account_name)

      output = capture_logs do
        client.get_messages
      end

      assert output.slice("sig=[REMOVED]")
      refute output.slice("sig=test-sig")
    end

    test "SAS key is not part of the logged request url in exceptions" do
      FakeVSOServer.reset!
      bad_message = Codespaces::StorageClient::Message.new(
        id: SecureRandom.uuid,
        pop_receipt: SecureRandom.uuid,
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: "insertion_time",
        expiration_time: "expiration_time",
        time_next_visible: "time_next_visible"
      )

      err = Codespaces::StorageClient.new(account_name: @account_name).delete_messages([bad_message]).first
      assert err.is_a? Exception
      assert err.to_s.exclude? FakeVSOServer::TEST_SIG
    end

    test "parsing of existing query params supports + and doesn't raise 404" do
      FakeVSOServer.reset!
      message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace, pop_receipt: "a+bc=")

      client = Codespaces::StorageClient.new(account_name: @account_name)
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]

      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible]
      )


      response = client.delete_messages([good_message]).first
      refute response.is_a? Exception
    end
  end

  context "#delete_messages" do
    test "accepts a collection of Messages and deletes them" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )

      results = Codespaces::StorageClient.new(account_name: @account_name).delete_messages([message])

      assert_equal 204, results.first.status
    end

    test "collects failures" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )
      bad_message = Codespaces::StorageClient::Message.new(
        id: SecureRandom.uuid,
        pop_receipt: SecureRandom.uuid,
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: 1.minute.ago.iso8601,
        expiration_time: 1.minute.from_now.iso8601,
        time_next_visible: 2.minutes.from_now.iso8601,
      )

      results = Codespaces::StorageClient.new(account_name: @account_name).delete_messages([good_message, bad_message])

      assert_instance_of Codespaces::StorageClient::BadResponseError, results.second
    end

    test "logs information for each message" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )
      bad_message = Codespaces::StorageClient::Message.new(
        id: SecureRandom.uuid,
        pop_receipt: SecureRandom.uuid,
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: 1.minute.ago.iso8601,
        expiration_time: 1.minute.from_now.iso8601,
        time_next_visible: 2.minutes.from_now.iso8601,
      )

      output = capture_logs do
        client = Codespaces::StorageClient.new(account_name: @account_name)
        client.delete_messages([good_message, bad_message])
        client.get_messages
      end

      assert_log_match(output, "status", "204")
      assert_log_match(output, "status", "404")
    end

    test "sends datadog distribution stat per request" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )
      bad_message = Codespaces::StorageClient::Message.new(
        id: SecureRandom.uuid,
        pop_receipt: SecureRandom.uuid,
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: 1.minute.ago.iso8601,
        expiration_time: 1.minute.from_now.iso8601,
        time_next_visible: 2.minutes.from_now.iso8601,
      )

      client = Codespaces::StorageClient.new(account_name: @account_name)
      client.delete_messages([good_message, bad_message])

      assert_dogstats_distribution(2, "codespaces.storage_client.delete_messages.latency")

      assert_dogstats_distribution("codespaces.client.storage.response.latency", tags: [
        "caller:delete_messages",
        "status:204",
        "codespaces_storage_client:delete_messages",
        "account_name:#{@account_name}"
      ])

      assert_dogstats_distribution("codespaces.client.storage.response.latency", tags: [
        "caller:delete_messages",
        "status:404",
        "codespaces_storage_client:delete_messages",
        "account_name:#{@account_name}"
      ])
    end

    test "returns a TimeoutError when Faraday request times out" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )

      Codespaces::StorageClient::Request.any_instance.expects(:execute).raises(Faraday::TimeoutError)

      client = Codespaces::StorageClient.new(account_name: @account_name)
      batch_message_deletion_result = client.delete_messages([good_message])

      assert_equal batch_message_deletion_result.first.class, Codespaces::StorageClient::TimeoutError
    end

    test "returns a ConnectionFailed error when Faraday connection fails" do
      FakeVSOServer.reset!
      queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
      good_message = Codespaces::StorageClient::Message.new(
        id: queued_message[:MessageId],
        pop_receipt: queued_message[:PopReceipt],
        body: "Not Used",
        dequeue_count: 1,
        insertion_time: queued_message[:InsertionTime],
        expiration_time: queued_message[:ExpirationTime],
        time_next_visible: queued_message[:TimeNextVisible],
      )

      Codespaces::StorageClient::Request.any_instance.stubs(:execute).raises(Faraday::ConnectionFailed.new("boom"))

      client = Codespaces::StorageClient.new(account_name: @account_name)
      batch_message_deletion_result = client.delete_messages([good_message])

      assert_equal batch_message_deletion_result.first.class, Codespaces::StorageClient::ConnectionFailed
    end
  end

  context "#get_messages" do
    test "gets messages from the Azure storage queue by name" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      messages = Codespaces::StorageClient.new(account_name: @account_name).get_messages

      assert_equal 1, messages.count
      body = messages.first.body
      assert_equal @codespace.guid, body["usageDetail"]["environments"].first["id"]
      assert_equal 1, messages.first.dequeue_count
    end

    test "gets messages from the Azure storage queue by name for PPE" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)
      create(:codespace_plan, vscs_target: :ppe)
      messages = Codespaces::StorageClient.new(account_name: @account_name, environment: :ppe).get_messages

      assert_equal 1, messages.count
      body = messages.first.body
      assert_equal @codespace.guid, body["usageDetail"]["environments"].first["id"]
      assert_equal 1, messages.first.dequeue_count
    end

    test "defaults to requesting 32 items from the queue" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      client = Codespaces::StorageClient.new(account_name: @account_name)
      client
        .expects(:parsed_storage_api)
        .with(:get,
          "/github-reporting-queue/messages?numofmessages=32",
          tags: ["codespaces_storage_client:get_messages", "account_name:#{@account_name}"]
        )
        .returns(Nokogiri::XML("<QueueMessagesList/>"))

      client.get_messages
    end

    test "supports a number_of_messages that requests a specific number of items from the queue" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      client = Codespaces::StorageClient.new(account_name: @account_name)
      client
        .expects(:parsed_storage_api)
        .with(:get,
          "/github-reporting-queue/messages?numofmessages=5",
          tags: ["codespaces_storage_client:get_messages", "account_name:#{@account_name}"]
        )
        .returns(Nokogiri::XML("<QueueMessagesList/>"))

      client.get_messages(number_of_messages: 5)
    end

    test "allows a visibility timeout to be specified" do
      FakeVSOServer.reset!
      FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)

      client = Codespaces::StorageClient.new(account_name: @account_name)
      client
        .expects(:parsed_storage_api)
        .with(:get,
          "/github-reporting-queue/messages?numofmessages=32&visibilitytimeout=600",
          tags: ["codespaces_storage_client:get_messages", "account_name:#{@account_name}"]
        )
        .returns(Nokogiri::XML("<QueueMessagesList/>"))

      client.get_messages(visibility_timeout: 10.minutes)
    end
  end

  test "request-id is part of error messages" do
    FakeVSOServer.reset!
    queued_message = FakeVSOServer.add_billing_messages_for(plan: @codespace.plan, codespaces: @codespace)[:QueueMessage]
    bad_message = Codespaces::StorageClient::Message.new(
      id: SecureRandom.uuid,
      pop_receipt: SecureRandom.uuid,
      body: "Not Used",
      dequeue_count: 1,
      insertion_time: 1.minute.ago.iso8601,
      expiration_time: 1.minute.from_now.iso8601,
      time_next_visible: 2.minutes.from_now.iso8601,
    )

    err = Codespaces::StorageClient.new(account_name: @account_name).delete_messages([bad_message]).first

    assert err.to_s.include? "Request-ID"
  end
end unless GitHub.enterprise?
