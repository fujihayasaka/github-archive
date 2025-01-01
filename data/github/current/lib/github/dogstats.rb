# typed: true
# frozen_string_literal: true

module GitHub
  class Dogstats < Datadog::Statsd
    def initialize(*, **kwargs)
      # See: https://github.com/github/monolith-platform/issues/31
      delay_serialization     = GitHub.environment.fetch("DOGSTATSD_DELAY_SERIALIZATION",      0).to_i == 1
      single_thread           = GitHub.environment.fetch("DOGSTATSD_SINGLE_THREAD",            0).to_i == 1
      sender_queue_size       = GitHub.environment.fetch("DOGSTATSD_SENDER_QUEUE_SIZE",       -1).to_i
      buffer_max_pool_size    = GitHub.environment.fetch("DOGSTATSD_BUFFER_MAX_POOL_SIZE",    -1).to_i
      buffer_max_payload_size = GitHub.environment.fetch("DOGSTATSD_BUFFER_MAX_PAYLOAD_SIZE", -1).to_i
      buffer_flush_interval   = GitHub.environment.fetch("DOGSTATSD_BUFFER_FLUSH_INTERVAL",   -1).to_i

      kwargs[:delay_serialization]      = true                     if delay_serialization
      kwargs[:single_thread]            = true                     if single_thread
      kwargs[:sender_queue_size]        = sender_queue_size        if -1 < sender_queue_size
      kwargs[:buffer_max_pool_size]     = buffer_max_pool_size     if -1 < buffer_max_pool_size
      kwargs[:buffer_max_payload_size]  = buffer_max_payload_size  if -1 < buffer_max_payload_size
      kwargs[:buffer_flush_interval]    = buffer_flush_interval    if -1 < buffer_flush_interval

      super

      # needed for extra telemetry tags
      self.tags = kwargs[:tags]

      GitHub.logger.info("GitHub::Dogstats initialised", {
        "gh.dogstats.host":                     self.host,
        "gh.dogstats.port":                     self.port,
        "gh.dogstats.socket_path":              self.socket_path,
        "gh.dogstats.delay_serialization":      self.delay_serialization,
        "gh.dogstats.sender_class_name":        self.sender_class_name,
        "gh.dogstats.sender_queue_size":        self.sender_queue_size,
        "gh.dogstats.buffer_max_pool_size":     self.buffer_max_pool_size,
        "gh.dogstats.buffer_max_payload_size":  self.buffer_max_payload_size,
        "gh.dogstats.buffer_flush_interval":    self.buffer_flush_interval
      })
    end

    def self.monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.duration(start, ending = nil)
      ending ||= case start
      when Float
        monotonic_time
      else
        Time.now
      end

      ((ending - start) * 1_000).round(5)
    end

    def batch
      warn "GitHub.dogstats.batch is unnecessary and deprecated. Just use GitHub.dogstats directly."
      yield self
    end

    def count(stat, count, opts = EMPTY_OPTIONS)
      super
    end

    def gauge(stat, value, opts = EMPTY_OPTIONS)
      super
    end

    def histogram(stat, value, opts = EMPTY_OPTIONS)
      super
    end

    def distribution(stat, value, opts = EMPTY_OPTIONS)
      super
    end

    def timing(stat, ms, opts = EMPTY_OPTIONS)
      super
    end

    def set(stat, value, opts = EMPTY_OPTIONS)
      super
    end

    def distribution_timing_since(stat, start, options = {})
      distribution(stat, GitHub::Dogstats.duration(start), options)
    end

    # Like GitHub.dogstats.timing, but records the duration since a given start
    # time. Useful when you would normally use GitHub.dogstats.time but want to
    # use a different stats key or options for different situations.
    #
    # @param [String] stat stat name
    # @param [Time or Float] start time or monotonic time
    # @param [Hash] opts the options to create the metric with
    # @option opts [Numeric] :sample_rate sample rate, 1 for always
    # @option opts [Array<String>] :tags An array of tags
    def timing_since(stat, start, opts = {})
      timing(stat, GitHub::Dogstats.duration(start), opts)
    end

    def distribution_time(stat, opts = EMPTY_OPTIONS)
      start = GitHub::Dogstats.monotonic_time
      yield
    ensure
      now = GitHub::Dogstats.monotonic_time
      distribution(stat, GitHub::Dogstats.duration(start, now), opts)
    end

    # This allows us to change the global tags that are sent with every
    # dogstats metric without having to create a new instance, which causes
    # issues with objects that store its reference
    def tags=(tags)
      unless tags.nil? || tags.is_a?(Array) || tags.is_a?(Hash)
        raise ArgumentError, "tags must be an array of string tags or a Hash"
      end

      @serializer = ::Datadog::Statsd::Serialization::Serializer.new(prefix: @prefix, global_tags: tags)

      delay_serialization     = self.delay_serialization
      sender_class_name       = self.sender_class_name
      sender_queue_size       = self.sender_queue_size
      buffer_max_pool_size    = self.buffer_max_pool_size
      buffer_max_payload_size = self.buffer_max_payload_size
      buffer_flush_interval   = self.buffer_flush_interval

      @forwarder.instance_eval do
        if telemetry
          telemetry.instance_eval do
            @global_tags = tags
            @serialized_tags = ::Datadog::Statsd::Serialization::TagSerializer.new(
              client: "ruby",
              client_version: ::Datadog::Statsd::VERSION,
              client_transport: @transport_type,
              client_delay_serialization: delay_serialization,
              client_sender_class_name: sender_class_name,
              client_sender_queue_size: sender_queue_size,
              client_buffer_max_pool_size: buffer_max_pool_size,
              client_buffer_max_payload_size: buffer_max_payload_size,
              client_buffer_flush_interval: buffer_flush_interval,
            ).format(tags)
          end
        end
      end
    end

    def delay_serialization
      @delay_serialization
    end

    def sender
      @forwarder&.instance_variable_get("@sender")
    end

    def sender_class_name
      sender&.class&.name
    end

    def sender_queue_size
      sender&.instance_variable_get("@queue_size")
    end

    def message_buffer
      sender&.instance_variable_get("@message_buffer")
    end

    def buffer_max_pool_size
      message_buffer&.instance_variable_get("@max_pool_size")
    end

    def buffer_max_payload_size
      message_buffer&.instance_variable_get("@max_payload_size")
    end

    def buffer_flush_interval
      sender&.instance_variable_get("@flush_timer")&.instance_variable_get("@interval")
    end
  end
end
