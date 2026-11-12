# frozen_string_literal: true

# Tests the baseline behaviour expected of our processor classes
#
# The specific test must implement the following methods:
# - processor        : an instance of the ApplicationProcessor child class
# - consumer         : a Dependabot.hydro_consumer object
# - decoded_payload  : a hydro message fixture
# - expected_tags    : a hash of values expected to be added to emitted metrics
RSpec.shared_examples "an application processor" do
  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: decoded_payload,
      timestamp: Time.now.utc,
      offset: 0,
      partition: 0,
      topic: topic,
      headers: { "X-GitHub-Tenant-ID" => "1234", "X-GitHub-Tenant" => "lugman-inc" },
    )
  end

  let(:topic) { "mock" }

  before do
    allow(processor).to receive(:sleep)
    allow(Flipper).to receive(:enabled?).and_return(false)
  end

  describe "single processor pausing" do
    let(:pause_flag) do
      processor.class.topic_pause_flag
    end

    it "sleeps while topic is paused, then complete as normal" do
      allow(Flipper).to receive(:enabled?).with(pause_flag).
        and_return(true, true, false)

      processor.process_with_consumer(message, consumer)

      expect(processor).to have_received(:sleep).twice

      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end

    it "sleeps while pause check fails due to database error" do
      allow(Dependabot::Exceptions).to receive(:report)
      calls = 0
      allow(Flipper).to receive(:enabled?).with(pause_flag) do
        unless calls >= 2
          calls += 1
          raise Trilogy::ConnectionClosed, "trilogy_auth_recv: TRILOGY_CLOSED_CONNECTION"
        end
        false
      end
      processor.process_with_consumer(message, consumer)

      expect(processor).to have_received(:sleep).twice
      expect(Dependabot::Exceptions).to have_received(:report).
        with(be_a(Trilogy::Error)).
        twice
      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end

    it "sleeps while pause check fails due to trilogy adapter database error" do
      allow(Dependabot::Exceptions).to receive(:report)
      calls = 0
      allow(Flipper).to receive(:enabled?).with(pause_flag) do
        unless calls >= 2
          calls += 1
          raise Trilogy::ConnectionClosed, "trilogy_auth_recv: TRILOGY_CLOSED_CONNECTION"
        end
        false
      end
      processor.process_with_consumer(message, consumer)

      expect(processor).to have_received(:sleep).twice
      expect(Dependabot::Exceptions).to have_received(:report).
        with(be_instance_of(Trilogy::ConnectionClosed)).
        twice
      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end

    it "does not sleep if topic isn't paused" do
      allow(Flipper).to receive(:enabled?).with(pause_flag).
        and_return(false)

      processor.process_with_consumer(message, consumer)

      expect(processor).not_to have_received(:sleep)

      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end
  end

  describe "instrumentation" do
    context "with a valid message" do
      it "marks the message as read" do
        processor.process_with_consumer(message, consumer)

        expect(consumer).to have_received(:mark_message_as_processed).
          with(message)
      end

      it "increments the started message metric" do
        processor.process_with_consumer(message, consumer)

        expect(MetricsClient).to have_received(:increment).
          with("consumer.process_message.started", tags: expected_tags)
      end

      it "increments the completed message metric" do
        processor.process_with_consumer(message, consumer)

        expect(MetricsClient).to have_received(:increment).
          with("consumer.process_message.completed", tags: expected_tags)
      end
    end
  end

  describe "hooks" do
    describe "#before_open" do
      it "touches a file indicating the processor is ready" do
        processor.before_open

        expect(File).to exist(described_class::READINESS_PATH)
      end
    end
  end

  describe "error handling" do
    # Dead letters send a stripped down set of tags to avoid parsing
    # the message itself to retrieve values.
    let(:dead_letter_tags) do
      { consumer: processor.options[:group_id] }
    end

    context "with a malformed hydro payload" do
      before do
        allow(processor).to receive(:process_message).
          and_raise(Google::Protobuf::ParseError, "Cannot parse")
        allow(Failbot).to receive(:report)
      end

      it "reports to failbot, marks it as read and counts a dead letter" do
        processor.process_with_consumer(message, consumer)

        expect(MetricsClient).to have_received(:increment).
          with("consumer.dead_letter", tags: dead_letter_tags)

        expect(Failbot).to have_received(:report).once
        expect(consumer).to have_received(:mark_message_as_processed).
          with(message)
      end
    end

    context "with a standard error" do
      before do
        allow(Failbot).to receive(:report)
        allow(processor).to receive(:process_message).
          and_raise(StandardError, "oh no!")
      end

      it "reports to failbot but does not mark it as read" do
        processor.process_with_consumer(message, consumer)

        expect(MetricsClient).to have_received(:increment).
          with("consumer.process_message.failed", tags: dead_letter_tags)

        expect(Failbot).to have_received(:report).once
        expect(consumer).not_to have_received(:mark_message_as_processed)
      end
    end
  end
end
