# typed: true
# frozen_string_literal: true

module GitHub
  module Logging
    class OTelLogger
      extend T::Helpers
      BACKWARDS_COMPATIBLE_MESSAGES = [
        :msg,
        "msg",
        :message,
        "message",
        :log_message,
        "log_message",
      ]

      SCROLLS_LEVEL_MAP = {
        "emerg"     => :fatal,
        "emergency" => :fatal,
        "alert"     => :fatal,
        "crit"      => :fatal,
        "critical"  => :fatal,
        "warning"   => :warn,
        "notice"    => :warn,
      }.freeze

      STRINGIFY_KEYS = [
        :exception, # raises an error when passed in and not an exception
        :duration, # would be omitted
        :payload, # raises an error when passed in
      ]

      def self.default_context
        @default_context ||= begin
          c = {
            env: GitHub::AppEnvironment.env,
            app: "github",
          }
          c[:enterprise] = true if GitHub.enterprise?
          c.freeze
        end
      end

      attr_reader :logger

      def initialize(opts = {})
        @logger = GitHub.logger
        @timestamp = opts[:timestamp] == true ? true : false
        @disabled = opts[:stream].is_a?(GitHub::Logger::NullStream)
      end

      # Public: Log data and/or wrap a block with start/finish
      #
      # data - A string, Hash, or object that responds to #to_hash
      # blk  - An optional block to be wrapped by start and finish log lines
      #
      # Example: log("foo")
      # Example: log(foo: "bar")
      # Example: log("foo") { do_something }
      # Example: log(foo: "bar") { do_something }
      def log(data, &blk)
        body = ""
        payload = {}

        if data.is_a?(String)
          body = data
          payload.merge!(log_message: data)
        else
          payload.merge!(data)
          msg_field = BACKWARDS_COMPATIBLE_MESSAGES.find { |field| payload[field].present? }
          body = payload[msg_field] if msg_field
        end

        return write(body, payload) unless blk

        res = begin
          start = Time.now
          start_payload = payload.merge(at: "start")
          write(body, start_payload)
          yield
        rescue StandardError => e # rubocop:todo Lint/RescueException
          exception_payload = payload.merge(
            at: "exception",
            reraise: true,
            class: e.class.name,
            message: e.message,
            exception_id: e.object_id.abs,
            elapsed: (Time.now - T.cast(start, Time)).to_f,
          )

          write(body, exception_payload)
          raise e
        end

        finish_payload = payload.merge(at: "finish", elapsed: (Time.now - start).to_f)
        write(body, finish_payload)
        res
      end

      # Public: add fields to any logs that are created within the block
      #
      # data - A Hash, or object that responds to #to_hash
      # blk  - A block to be wrapped by start and finish log lines
      #
      # Example: with_context(foo: "bar") { log("boo") }
      # Example: with_context(StandardError.new("foo")) { log("boo") }
      def with_context(data, &blk)
        return unless blk
        data = {}.merge(data) # do this to handle types the way that Scrolls does
        logger.with_named_tags(data) do # adds data to named_tags
          blk.call
        end
      end

      # Public: Log an exception (if it has a backtrace)
      #
      # e    - An exception to pass to the logger
      # data - A hash of key/values to log
      #
      def log_exception(e, data = nil)
        return unless e.backtrace

        lines = e.backtrace.map { |line| line.gsub(/[`'"]/, "") }
        return if lines.empty?

        payload = case data
        when String
          { "log_message" => data }
        when Hash
          data
        else
          {}
        end

        payload = self.class.default_context.merge(payload)

        payload.merge!(
          at:           "exception",
          class:        e.class,
          message:      e.message,
          exception_id: e.object_id.abs,
          site: lines.join('\n'),
        )

        log(payload)
      end

      def context
        logger.named_tags
      end

      private

      def write(body, payload)
        return if @disabled
        payload.merge!(now: Time.now.utc) if @timestamp
        combined_tags = self.class.default_context.merge(logger.named_tags).merge(payload)

        STRINGIFY_KEYS.each do |key|
          next unless combined_tags[key]
          combined_tags[key.to_s] = combined_tags.delete(key)
        end

        nilify!(combined_tags)
        level = get_level(combined_tags)
        logger.send(level, body, combined_tags)
      end

      def get_level(payload)
        level = payload[:level] || payload["level"] || :info
        level = SCROLLS_LEVEL_MAP.fetch(level.to_s, level) # try to lookup Scrolls level
        SemanticLogger::Levels.index(level) # check if level is valid (raises if not)
        level
      end

      def nilify!(payload)
        payload.each do |key, value|
          payload[key] = "nil" if value.nil?
        end
      end
    end
  end
end
