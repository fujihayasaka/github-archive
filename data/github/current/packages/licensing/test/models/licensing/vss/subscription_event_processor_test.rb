# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::Vss::SubscriptionEventProcessorTest < GitHub::TestCase
  test "creates an event record and enqueues a job to process it" do
    processor = Licensing::Vss::SubscriptionEventProcessor.new

    message = "Hello world"
    processor.process(message)

    event = Licensing::Vss::VssSubscriptionEvent.last

    assert_equal message, event.payload
    assert T.must(event).unprocessed?
    assert_enqueued_with(job: Licensing::VssSubscriptionEventProcessingJob, args: [event])
  end

  test "does not save event if job is not enqueued successfully" do
    processor = Licensing::Vss::SubscriptionEventProcessor.new

    Licensing::VssSubscriptionEventProcessingJob.expects(:perform_later).raises(RuntimeError)

    assert_raises RuntimeError do
      processor.process("Hello world")
    end

    assert Licensing::Vss::VssSubscriptionEvent.none?
  end

  test "sets some failbot context" do
    _processor = Licensing::Vss::SubscriptionEventProcessor.new
    assert_equal({ "codespace.name" => "Licensing::Vss::SubscriptionEventProcessor" }, Failbot.context.last)
  end
end
