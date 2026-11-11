# frozen_string_literal: true

class ApplicationProcessor < Hydro::Processor
  set_callback :open, :before, :before_open

  GROUP_ID_PREFIX = "dependabot_api"
  PAUSE_FLAG_PREFIX = "hydro_pause"
  READINESS_PATH = "/tmp/hydro_started"

  # Dead Letter Error classes are exceptions we do not block on.
  #
  # This means that instead of retrying the message until it is eventually
  # ingested, we discard the affected message and move on.
  #
  # Things to consider when dead lettering an error:
  #
  # 1. Is this error representative of an issue we could encounter again?
  # 2. Are we adding the narrowest possible error class to our dead letter list?
  #   - Errors that could occur in any processor like ArgumentError or
  #     ActiveRecord::RecordNotFound represent bad candidates to dead letter
  #   - Consider re-raising the error as a distinct error class as close to the
  #     source as possible within the single affected processor
  # 3. What is the impact of affected message(s) being dropped on the customer
  #    experience?
  #
  # Each dead letter class should indicate whether it is reported to the error
  # tracker with true/false
  DEAD_LETTER_ERRORS = {
    Google::Protobuf::ParseError => true,
  }.freeze

  class_attribute :last_checked_at
  class_attribute :paused

  def self.group_name(group_name)
    @group_name = group_name
    options[:group_id] = [GROUP_ID_PREFIX, @group_name].join("_")
    @group_name
  end

  def self.handle_topic(pattern, handler_class)
    MultiTopicProcessor.multi_subscribe(pattern, handler_class) if Dependabot.enterprise? || Rails.env.development?

    @handler_class = handler_class
    subscribe_to(pattern)
  end

  def self.handler
    raise "A processor must define a handler_class!" unless defined? @handler_class

    @handler_class
  end

  def self.slug
    raise "A processor must define a group_name!" unless defined? @group_name

    @group_name
  end

  def self.topic_pause_flag
    @topic_pause_flag ||= [PAUSE_FLAG_PREFIX, slug].join("_")
  end

  def self.reset_pause_cache
    self.paused = nil
    self.last_checked_at = nil
  end

  def self.topic_paused?
    if last_checked_at.nil? || last_checked_at < 30.seconds.ago
      self.paused = Dependabot.redis.get(topic_pause_flag) == "true"
      self.last_checked_at = Time.now.utc
    end

    paused
  rescue Redis::BaseError => e
    Dependabot::Exceptions.report(e)
    true
  end

  def self.paused?
    topic_paused?
  end

  # These settings can be adjusted according to
  # https://github.com/zendesk/ruby-kafka#balancing-throughput-and-latency
  # Here we're using the defaults suggested in
  # https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/guides/deploying-consumers/
  def self.options
    @options ||= {
      min_bytes: 5.kilobytes,
      max_wait_time: 1.second,
      max_bytes_per_partition: 1.megabyte,
      start_from_beginning: false,
      # We want to explicitly control when messages are processed so we can
      # retry potential race conditions without raising an exception.
      automatically_mark_as_processed: false,
    }
  end

  def self.action_class(action_class)
    @action_class = action_class
  end

  def self.action
    @action_class
  end

  # Called before the consumer loop starts
  def before_open
    FileUtils.touch(READINESS_PATH)
  end

  def process_with_consumer(message, consumer)
    # Pause before starting the batch if required
    # Note: pausing is currently not supported in GHES / when using the
    # MultiTopicProcessor
    check_for_pause

    setup_exception_context(message)

    instrument_with_timing(message) do
      process_message(message)

      consumer.mark_message_as_processed(message)
    end
  rescue *dead_letter_error_classes(message.topic) => e
    Dependabot::Exceptions.push("gh.dependabot_api.hydro.handled_consumer_error": true)

    # We should notice the error unless this class is deliberately muted.
    Dependabot::Exceptions.report(e, error_context(e)) if dead_letter_errors(message.topic).fetch(e.class, true)

    # For any known error case, we should make the message as read so we
    # don't keep trying it indefinitely with no expectation of success.
    consumer.mark_message_as_processed(message)

    # We should increment the Dead Letter count to acknowledge the message rejection
    MetricsClient.increment("consumer.dead_letter", tags: mandatory_tags)

    Rails.logger.info "Dead Letter: #{e.class} - #{e.message}"
  rescue StandardError => e
    Dependabot::Exceptions.push("gh.dependabot_api.hydro.handled_consumer_error": false)

    # We must notice the error, but avoid re-raising so we do not break the loop.
    Dependabot::Exceptions.report(e, error_context(e))

    MetricsClient.increment("consumer.process_message.failed", tags: mandatory_tags)

    Rails.logger.info "Message ingestion failed!"
  end

  def process_message(message)
    MetricsClient.increment("consumer.process_message.started", tags: tags(message))

    # We emit only the manditory tags for timing to minimise the datadog
    # indexes we create since timing is not as useful to drill down
    MetricsClient.time("consumer.handler_run", tags: mandatory_tags) do
      ActiveRecord::Base.connection_pool.with_connection do
        self.class.handler.run(message)
      end
    end

    MetricsClient.increment("consumer.process_message.completed", tags: tags(message))
  end

  private

  def setup_exception_context(message)
    Dependabot::Exceptions.reset!
    Dependabot::Exceptions.push(
      "messaging.kafka.consumer.group": group_id,
      "gh.hydro.msg.offset": message.offset,
      "gh.hydro.msg.partition": message.partition,
      "gh.hydro.msg.topic": message.topic,
    )
  end

  def instrument_with_timing(message)
    Dependabot::Logger.info(
      msg: "Processing Hydro message",
      "messaging.kafka.consumer.group": group_id,
      "gh.hydro.msg.offset": message.offset,
      "gh.hydro.msg.partition": message.partition,
      "gh.hydro.msg.topic": message.topic,
    )
    start_time = Time.now.in_time_zone

    yield

    duration = Time.now.in_time_zone - start_time
    Dependabot::Logger.info(
      msg: "Processed Hydro message",
      "messaging.kafka.consumer.group": group_id,
      "gh.hydro.msg.offset": message.offset,
      "gh.hydro.msg.partition": message.partition,
      "gh.hydro.msg.topic": message.topic,
      "gh.timing.duration_seconds": duration,
    )
  end

  def tags(message)
    tags_for(message).merge(mandatory_tags)
  end

  # Shim to allow handlers to add additional specific dead letter errors
  def dead_letter_errors(_)
    handler = self.class.handler
    custom_errors = handler.respond_to?(:dead_letter_errors) ? handler.dead_letter_errors : {}

    DEAD_LETTER_ERRORS.merge(custom_errors)
  end

  def dead_letter_error_classes(topic)
    dead_letter_errors(topic).keys
  end

  def check_for_pause
    while self.class.paused?
      Rails.logger.info "#{group_id} paused."
      sleep(1)
    end
  end

  # A per-message tag helper which may be defined in specific processors as
  # required.
  def tags_for(_message)
    {}
  end

  # Implements tags that must be applied to all messages to identify the
  # consumer group.
  def mandatory_tags
    {
      consumer: group_id,
    }
  end

  def error_context(error)
    transaction = self.class.to_s
    rollup = Digest::SHA256.hexdigest("#{error.class}#{transaction}")
    { rollup: rollup, transaction: transaction }
  end
end
