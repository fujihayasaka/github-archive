# frozen_string_literal: true

# Tests the baseline behaviour expected of our processor classes
#
# The specific test must implement the following methods:
# - processor        : an instance of the ApplicationProcessor child class
# - consumer         : a Dependabot.hydro_consumer object
# - decoded_payload  : a hydro message fixture
# - expected_tags    : a hash of values expected to be added to emitted metrics
RSpec.shared_examples "an application processor" do
  include ActiveSupport::Testing::TimeHelpers
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
  let(:redis) { Dependabot.redis }

  before do
    allow(processor).to receive(:sleep)
    redis.flushdb
  end

  describe "single processor pausing" do
    let(:pause_flag) do
      processor.class.topic_pause_flag
    end

    it "sleeps while topic is paused, then complete as normal" do
      allow(processor.class).to receive(:paused?).
        and_return(true, true, false)

      processor.process_with_consumer(message, consumer)

      expect(processor).to have_received(:sleep).twice

      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end

    it "waits for at least 30s between redis checks" do
      if processor.class.slug == "repository_dependency_update"
        skip "Because there are multiple processors with this slug, caching behavior is unpredictable"
      end

      ProcessorManager.pause(processor.class.slug)
      processor.class.paused? # cache the paused state

      travel 10.seconds do
        expect(processor.class.topic_paused?).to be true
        expect(processor.class.last_checked_at).not_to be_nil
        expect(Time.now.utc - processor.class.last_checked_at).to be > 9.seconds
      end

      travel 40.seconds do
        expect(Time.now.utc - processor.class.last_checked_at).to be > 31.seconds
        expect(processor.class.topic_paused?).to be true
        expect(Time.now.utc - processor.class.last_checked_at).to be < 1.second
      end

      ProcessorManager.resume(processor.class.slug)
      expect(processor.class.topic_paused?).to be false
    end

    it "sleeps while pause check fails due to redis error" do
      processor.class.reset_pause_cache
      allow(Dependabot).to receive(:redis).and_return(redis)

      allow(Dependabot::Exceptions).to receive(:report)
      calls = 0
      allow(redis).to receive(:get).with(pause_flag) do
        unless calls >= 2
          calls += 1
          raise Redis::BaseError, "redis error"
        end
        "false"
      end
      processor.process_with_consumer(message, consumer)

      expect(processor).to have_received(:sleep).twice
      expect(Dependabot::Exceptions).to have_received(:report).
        with(be_a(Redis::BaseError)).
        twice
      expect(consumer).to have_received(:mark_message_as_processed).
        with(message).once
    end

    it "does not sleep if topic isn't paused" do
      allow(Dependabot.redis).to receive(:get).with(pause_flag).
        and_return("false")

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
