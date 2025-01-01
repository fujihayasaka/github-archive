# typed: true
# frozen_string_literal: true

module GitHub
  class NullDogstatsD
    attr_accessor :host
    attr_accessor :port
    attr_accessor :namespace
    attr_accessor :max_buffer_size

    def initialize(*)
    end

    def increment(stat, opts = {})
      ensure_valid_opts(opts)
    end

    def decrement(stat, opts = {})
      ensure_valid_opts(opts)
    end

    def count(stat, count, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(count)
    end

    def gauge(stat, value, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(value)
    end

    def histogram(stat, value, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(value)
    end

    def distribution(stat, value, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(value)
    end

    def distribution_timing_since(stat, value, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(GitHub::Dogstats.duration(value))
    end

    def distribution_time(stat, opts = {})
      ensure_valid_opts(opts)
      yield
    end

    def timing(stat, ms, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_value(ms)
    end

    def timing_since(stat, start, opts = {})
      ensure_valid_opts(opts)
      ensure_valid_start(start)
    end

    def time(stat, opts = {})
      ensure_valid_opts(opts)
      yield
    end

    def set(stat, value, opts = {})
      ensure_valid_opts(opts)
    end

    def service_check(name, status, opts = {})
      ensure_valid_opts(opts)
    end

    def event(title, text, opts = {})
      ensure_valid_opts(opts)
    end

    def batch
      warn "GitHub::NullDogstatsD#batch is unnecessary and deprecated. Just use other GitHub::NullDogstatsD methods directly."
      yield self
    end

    def tags
      []
    end

    def tags=(tags)
    end

    def flush(flush_telemetry: true, sync: true)
    end

    def close(flush: true)
      flush(sync: true) if flush
    end

    private

    def ensure_valid_opts(opts)
      raise ArgumentError, "Expected hash, got #{opts.class} " unless opts.instance_of?(Hash)
      if (tags = opts[:tags])
        unless tags.instance_of?(Array) || tags.instance_of?(Hash)
          raise ArgumentError, "Expected `tags` to be an array or hash, but was #{tags.class}"
        end
      end
    end

    def ensure_valid_value(value)
      raise ArgumentError unless value.is_a?(Numeric)
    end

    def ensure_valid_start(value)
      raise ArgumentError if !value.is_a?(Time) && !value.is_a?(Float)
    end
  end
end
