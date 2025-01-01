# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditCheckStatusPollJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    skip unless GitHub.billing_enabled?
  end

  setup do
    @message1 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 1), location: nil)
    @message2 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 2, status: "Rejected"), location: nil)
    @message3 = GitHub::AzureServiceBus::Message.new(body: generate_message(request_id: 3, status: "Pending Review"), location: nil)
    @customer1 = create(:credit_card_user).customer
    @customer2 = create(:credit_card_user).customer
    @customer3 = create(:credit_card_user).customer
    @credit_check1 = Billing::CreditCheck.create(customer_id: @customer1.id, request_id: "GIT.1")
    @credit_check2 = Billing::CreditCheck.create(customer_id: @customer2.id, request_id: "GIT.2")
    @credit_check3 = Billing::CreditCheck.create(customer_id: @customer3.id, request_id: "GIT.3")

    @client = GitHub::AzureServiceBus::QueueClient.new(queue_name: "test", connection_string: "test")
    @client.stubs(:peek_lock_message).returns(@message1, @message2, @message3)
    @client.stubs(:delete_message)
    CreditCheckStatusPollJob.any_instance.stubs(:service_bus_client).returns(@client)
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

  test "runs on the credit_check queue" do
    assert_enqueued_jobs 1, queue: :credit_check do
      CreditCheckStatusPollJob.perform_later
    end
  end

  test "processes and stores credit checks" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @client.expects(:delete_message).once.with(@message1)
    @client.expects(:delete_message).once.with(@message2)
    @client.expects(:delete_message).never.with(@message3)
    assert_predicate @customer1.credit_check, :pending_review?
    assert_predicate @customer2.credit_check, :pending_review?


    CreditCheckStatusPollJob.stub_const(:MAX_CREDIT_CHECKS_TO_PROCESS, 2) do
      CreditCheckStatusPollJob.perform_now
    end

    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["polling"]).length
    assert_equal 2, stats.increments("get_credit_check_status_message_job", tags: ["processing"]).length
    assert_equal 2, stats.increments("get_credit_check_status_message_job", tags: ["processed"]).length
    assert_predicate @customer1.reload.credit_check, :approved?
    assert_predicate @customer2.reload.credit_check, :rejected?
  end

  test "reports to sentry when CreditCheck customer is not found" do
    @customer1.destroy!
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @client.expects(:delete_message).once

    CreditCheckStatusPollJob.stub_const(:MAX_CREDIT_CHECKS_TO_PROCESS, 1) do
      CreditCheckStatusPollJob.perform_now
    end

    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["polling"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["processing"]).length
    assert_equal 1, stats.increments("get_credit_check_status_message_job", tags: ["processed"]).length
    report = Failbot.reports.last
    assert_equal "CreditCheckStatusPollJob::CreditCheckMissing", Failbot.exception_classname_from_hash(report)
    assert_equal "CreditCheck not found for request_id: GIT.1 with received status: approved", Failbot.exception_message_from_hash(report)
  end
end
