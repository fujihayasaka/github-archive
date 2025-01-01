# frozen_string_literal: true

module Ingest
  class Processor < Hydro::Processor
    require_relative "./processor/best_effort_message_handler.rb"
    require_relative "./processor/strict_message_handler.rb"

    # socket_timeout should always be slightly longer than session/rebalance
    SOCKET_TIMEOUT           = 320.seconds
    SESSION_TIMEOUT          = 300.seconds
    REBALANCE_TIMEOUT        = 300.seconds
    OFFSET_COMMIT_INTERVAL   = 120.seconds
    READINESS_PORT = ENV.fetch("READINESS_PORT", 8888).to_i

    MESSAGE_HANDLERS = { best_effort: BestEffortMessageHandler.new, strict: StrictMessageHandler.new }

    attr_reader :debug, :schema

    if Rails.env.production?
      before_open do
        # Create a readiness probe for deployments
        Thread.new do
          Socket.tcp_server_loop(READINESS_PORT) do |conn, addr|
            conn.close
          end
        end
      end
    end

    # Processors in dg-api were processing messages in a combination of best_effort (marking messages as processed)
    # and strict (crashing the process) unintentionally before we formalized these notions, now everything is
    # defaulted to best_effort.
    def initialize(name:, debug: false, message_handling: :best_effort)
      @config = Rails.application.config_for(:kafka).with_indifferent_access
      @name = name
      @schema = @config.fetch("#{@name}_schema")
      @debug = debug
      @message_handler = MESSAGE_HANDLERS[message_handling]
      if @message_handler.nil?
        raise ArgumentError.new("Expected a message_handling argument of either :best_effort or :strict")
      end

      options.merge!({
        group_id: @debug ? "dependency_graph_#{@name}_debug": @config.fetch("#{@name}_consumer_group"),
        subscribe_to: @config.fetch("#{@name}_topic"),
        seed_brokers: @config.fetch(:hydro_seed_brokers),
        client_id: @config.fetch(:client_id),
        fetcher_max_queue_size: 100,
        start_from_beginning: @config.fetch(:start_from_beginning),
        automatically_mark_as_processed: true,
        socket_timeout: SOCKET_TIMEOUT,
        session_timeout: SESSION_TIMEOUT,
        rebalance_timeout: REBALANCE_TIMEOUT,
        offset_commit_interval: OFFSET_COMMIT_INTERVAL,
        logger: DependencyGraph.logger
      })

      options[:subscribe_to] = /(#{Regexp.escape(options[:subscribe_to])})/ if Rails.env.test?
    end

    def self.run
      new.run
    end

    def run
      client.run(self, consumer: consumer, shutdown_signals: [:INT, :TERM])
    end

    # BE CAREFUL - the first argument here can be a "batch" (array of messages!)
    # if Hydro::Processor.batching? method returns true!
    def process_with_consumer(message, consumer)
      DependencyGraph.logger.log_and_failbot_context(get_logging_context(message)) do
        Rails.application.executor.wrap do
          @message_handler.handle_message_and_errors(options) do
            if debug
              consume_debug_message(message)
            else
              consume_message(message)
            end
          end
        end
      end
    # Unconventional code: This is the last place we can make sure identifiable info gets logged to Failbot,
    # and it's "worth it" to have a little extra risk / unconventional code to make sure that we
    # are able to identify potentially surprising errors (like SystemStack) by repo / manifest name
    # and other message specific details (like offset).
    # It's assumed that a processor implementation that is re-raising is intentionally trying to crash
    # the process, and will be relying on our logging here as well.
    # We make sure to reraise the error here, as well, so we're comfy violating https://rubystyle.guide/#no-blind-rescues .
    rescue Exception => e # rubocop:disable Lint/RescueException
      @message_handler.react_to_crashing_message(e, consumer, message)
      raise e
    end

    # ** WARNING! **
    # Overriding Hydro::Processor's "batching?" method CONSIDERED HARMFUL!
    #
    # Changing the value of this flag (default "false" as of client 2.x version)
    # changes the ARGUMENT TYPE of the first arg of "process" and "process_with_consumer"
    # from an OBJECT to an ARRAY. Don't believe me? Behold:
    # https://github.com/github/hydro-client-ruby/blob/main/lib/hydro/processor.rb#L68-L83
    #
    # I hereby charge the miscreant Yukihiro Matsumoto with crimes against computer science!
    # I offer 100 gold pieces to the one who BRINGS ME HIS HEAD!
    def batching?
      # continue to override this as a "pin" against future client upgrades!
      false
    end

    def consume_message(message)
      raise NotImplementedError
    end

    def consume_debug_message(message)
      puts message
    end

    def get_baseline_logging_context(hydro_message)
      # TODO
      {
        "gh.dependency_graph.etl.step.name" => "etl.#{options[:subscribe_to]}",
        "gh.hydro.msg.key" => hydro_message.key,
        "gh.hydro.msg.offset" => hydro_message.offset,
        "gh.hydro.msg.partition" => hydro_message.partition,
        "gh.hydro.msg.topic" => hydro_message.topic
      }
    end

    def get_processor_specific_logging_context(hydro_message)
      # A processor implementor can override this to provide their own
      # failbot context that will be merged in and block executed during
      # processing.
      {}
    end

    def get_logging_context(hydro_message)
      get_baseline_logging_context(hydro_message).merge(get_processor_specific_logging_context(hydro_message))
    end

    def publish(message, topic: nil)
      publisher.publish(message, schema: schema, topic: topic)
    rescue Google::Protobuf::ParseError, ArgumentError => e
      Instrument.increment("etl.encode_failure", topic: options[:subscribe_to])
      Failbot.report(e, "gh.dependency_graph.etl.step.name" => "etl.ingest_#{@options[:subscribe_to]}.encode")
    end

    def flush
      publisher.flush_batch
    end

    # TEMPORARY! can be removed after static manifest snapshot jobs move to DS-API
    def snapshots_enabled_for?(message)
      # For the PoC, we only care about NPM lockfiles
      message.dig(:manifest_file, :filename)&.strip&.downcase == "package-lock.json" &&
        message.dig(:snapshot_metadata)
    end

    def spec_reset
      publisher.sink.reset if Rails.env.test?
    end

    def spec_publisher
      publisher if Rails.env.test?
    end

    def spec_consumer
      consumer if Rails.env.test?
    end

    private

    def consumer
      @consumer ||= client.consumer(**options)
    end

    def publisher
      @publisher ||= client.publisher(**publisher_options)
    end

    def publisher_options
      @publisher_options ||= {
        seed_brokers: options[:seed_brokers],
        client_id: options[:client_id],
        async: false,
        topic_format_options: { format_version: Hydro::Topic::FormatVersion::V1 },
      }
    end

    def client
      target_environment = DependencyGraphAPI.enterprise? ? "ghes" : Rails.env
      @client ||= Hydro::Client.new(environment: target_environment)
    end
  end
end
