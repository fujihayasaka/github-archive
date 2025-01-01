require "rails_helper"

module Ingest
  describe Processor::BestEffortMessageHandler do
    it "logs and handles standard error" do
      test_handler = Processor::BestEffortMessageHandler.new
      error_to_raise = StandardError.new "Some standard error"
      expect(Failbot).to receive(:report).once.with(error_to_raise)
      expected_subscribe_to = "SomeSubscribeTo"
      expect(Instrument).to receive(:increment).once.with("etl.lost_best_effort_message", { topic: expected_subscribe_to })

      test_handler.handle_message_and_errors({ subscribe_to: expected_subscribe_to }) do
        raise error_to_raise
      end
    end

    it "logs and handles system stack error" do
      test_handler = Processor::BestEffortMessageHandler.new
      error_to_raise = SystemStackError.new "Some system stack error"
      expect(Failbot).to receive(:report).once.with(error_to_raise)
      expected_subscribe_to = "SomeSubscribeTo"
      expect(Instrument).to receive(:increment).once.with("etl.lost_best_effort_message", { topic: expected_subscribe_to })

      test_handler.handle_message_and_errors({ subscribe_to: expected_subscribe_to }) do
        raise error_to_raise
      end
    end

    it "marks message as processed on big bad errors" do
      test_handler = Processor::BestEffortMessageHandler.new
      error_to_raise = NoMemoryError.new "Some OOM error"
      expect(Failbot).to receive(:report).once.with(error_to_raise)

      consumer = double("Some Consumer")
      message = double("Some Message")
      expect(consumer).to receive(:mark_message_as_processed).once.with(message)
      expect(consumer).to receive(:commit_offsets).once.with(message)
      test_handler.react_to_crashing_message(error_to_raise, consumer, message)
    end
  end
end
