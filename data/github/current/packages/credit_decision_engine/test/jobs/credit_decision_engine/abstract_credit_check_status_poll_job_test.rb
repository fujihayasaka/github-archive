# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::AbstractCreditCheckStatusPollJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  class TestCreditCheckStatusPollJob < CreditDecisionEngine::AbstractCreditCheckStatusPollJob
    CREDIT_CHECKS_TO_PROCESS = 1

    def perform
      process_credit_checks(credit_checks_to_process: CREDIT_CHECKS_TO_PROCESS)
    end

    def process_credit_check(request_id:, status:)
    end
  end

  fixtures do
    skip unless GitHub.billing_enabled?
  end

  setup do
    @message1 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 1), location: nil)
    @message2 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 2, status: "Rejected"), location: nil)
    @message3 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 3, status: "Pending Review"), location: nil)

    @client = GitHub::AzureServiceBus::QueueClient.new(queue_name: "test", connection_string: "test")
    @client.stubs(:peek_lock_message).returns(@message1, @message2, @message3)
    @client.stubs(:delete_message)
    TestCreditCheckStatusPollJob.any_instance.stubs(:service_bus_client).returns(@client)
  end

  def generate_message(request_id:, status: "Approved")
    {
      RequestNumber: "GIT.#{request_id}",
      SourceReferenceID: nil,
      Status: status,
      Amount: Random.rand(1000.00..10000.00),
      FinalResultDate: "2024-03-27T23:27:43.2418609Z",
      Notes: nil,
      Cid: nil,
      AccountId: nil
    }.to_json
  end

  test "successfully processes a credit check" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @client.expects(:delete_message).once.with(@message1)
    @client.expects(:delete_message).never.with(@message2)
    @client.expects(:delete_message).never.with(@message3)


    TestCreditCheckStatusPollJob.perform_now

    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["polling"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["processing"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["processed"]).length
  end

  test "successfully processes multiple credit checks" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @messages_to_process = 3
    @client.expects(:delete_message).once.with(@message1)
    @client.expects(:delete_message).once.with(@message2)
    @client.expects(:delete_message).once.with(@message3)

    TestCreditCheckStatusPollJob.stub_const(:CREDIT_CHECKS_TO_PROCESS, 3) do
      TestCreditCheckStatusPollJob.perform_now
    end

    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["polling"]).length
    assert_equal 3, stats.increments("get_credit_check_status_message_job", tags: ["processing"]).length
    assert_equal 3, stats.increments("get_credit_check_status_message_job", tags: ["processed"]).length
  end

  test "reports to sentry when it fails to parse the message" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    message = JSON.parse(generate_message(request_id: 404)).except("RequestNumber").to_json
    error_message = GitHub::AzureServiceBus::Message.new(body: message, location: nil)
    @client.unstub(:peek_lock_message)
    @client.stubs(:peek_lock_message).returns(error_message)
    @client.expects(:delete_message).never

    assert_raises(CreditDecisionEngine::ServiceBusResponseError) do
      TestCreditCheckStatusPollJob.perform_now
    end

    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["polling"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["processing"]).length
    assert_equal 0, stats.increments("get_credit_check_status_message_job", tags: ["processed"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["failed"]).length
    report = Failbot.reports.last
    assert_equal "CreditDecisionEngine::ServiceBusResponseError", Failbot.exception_classname_from_hash(report)
    assert_equal "Request number: , reference number: , errors: missing RequestNumber", Failbot.exception_message_from_hash(report)
  end
end
