# typed: true
# frozen_string_literal: true

require "github/dogstats"

module GitHub
  class MemoryDogstatsD
    attr_accessor :host
    attr_accessor :port
    attr_accessor :tags
    attr_accessor :namespace
    attr_accessor :max_buffer_size
    class Operation
      attr_reader :name, :args

      def initialize(name, *args)
        @name = name
        @args = args
        validate_args
      end

      def taggable?
        false
      end

      def ==(other)
        name == other.name && args == other.args
      end

      private

      def validate_args
        last_arg = @args.last
        unless last_arg.is_a?(Hash)
          raise ArgumentError.new("@args should be a Hash but it's #{last_arg} (#{last_arg.class})")
        end
      end
    end

    class StatOperation < Operation

      def stat
        args[0]
      end

      def value
        args[1]
      end

      def options
        args[2]
      end

      def tags
        Set.new(options[:tags])
      end

      def tags=(tags)
        options[:tags] = tags
      end

      def sample_rate
        options[:sample_rate]
      end

      def taggable?
        true
      end

      # Override inspect to make test assertion output more helpful
      def inspect
        %Q{#<dogstats.#{name}("#{stat}", #{value.inspect}, #{options.to_json})>}
      end

      private

      def validate_args
        super
        raise ArgumentError.new("value should be a Numeric but it's '#{value}' (#{value.class})") unless value.is_a?(Numeric)
      end
    end

    attr_reader :operations

    def initialize
      reset
    end

    def increment(stat, options = {})
      @operations << StatOperation.new(:increment, stat, 1, options)
    end

    def decrement(stat, options = {})
      @operations << StatOperation.new(:decrement, stat, -1, options)
    end

    def count(stat, count, options = {})
      @operations << StatOperation.new(:count, stat, count, options)
    end

    def gauge(stat, value, options = {})
      @operations << StatOperation.new(:gauge, stat, value, options)
    end

    def histogram(stat, value, options = {})
      @operations << StatOperation.new(:histogram, stat, value, options)
    end

    def distribution(stat, value, options = {})
      @operations << StatOperation.new(:distribution, stat, value, options)
    end

    def distribution_timing_since(stat, start, options = {})
      distribution(stat, GitHub::Dogstats.duration(start), options)
    end

    def distribution_time(stat, options = {})
      start = Time.now
      yield
    ensure
      distribution(stat, GitHub::Dogstats.duration(start), options)
    end

    def timing(stat, ms, options = {})
      @operations << StatOperation.new(:timing, stat, ms, options)
    end

    def timing_since(stat, start, options = {})
      timing(stat, GitHub::Dogstats.duration(start), options)
    end

    def time(stat, options = {})
      start = Time.now
      yield
    ensure
      timing(stat, GitHub::Dogstats.duration(start), options)
    end

    def set(stat, value, options = {})
      @operations << StatOperation.new(:set, stat, value, options)
    end

    def service_check(name, status, options = {})
      @operations << StatOperation.new(:service_check, name, status, options)
    end

    def event(title, text, options = {})
      @operations << Operation.new(:event, title, text, options)
    end

    def batch
      warn "GitHub::MemoryDogstatsD#batch is unnecessary and deprecated. Just use other GitHub::MemoryDogstatsD methods directly."
      yield self
    end

    def increments(stat = nil, options = {})
      operations_matching(:increment, stat, options)
    end

    def decrements(stat = nil, options = {})
      operations_matching(:decrement, stat, options)
    end

    def counts(stat = nil, options = {})
      operations_matching(:count, stat, options)
    end

    def gauges(stat = nil, options = {})
      operations_matching(:gauge, stat, options)
    end

    def histograms(stat = nil, options = {})
      operations_matching(:histogram, stat, options)
    end

    def distributions(stat = nil, options = {})
      operations_matching(:distribution, stat, options)
    end

    def timings(stat = nil, options = {})
      operations_matching(:timing, stat, options)
    end

    def sets(stat = nil, options = {})
      operations_matching(:set, stat, options)
    end

    def service_checks(stat = nil, options = {})
      operations_matching(:service_check, stat, options)
    end

    def events
      operations_matching(:event)
    end

    def reset
      @operations = []
      @flushed_synchronously = false
      @telemetry_flushed = false
    end

    def flush(flush_telemetry: false, sync: false)
      @flushed_synchronously = sync
      @telemetry_flushed = flush_telemetry
    end

    def close(flush: true)
      flush(sync: true) if flush
    end

    def operations_matching(name, stat = nil, options = {})
      @operations.select do |operation|
        operation.name == name &&
          (stat ? operation.stat == stat : true) &&
          (options[:tags] ? operation.taggable? && operation.tags >= Set.new(options[:tags]) : true)
      end
    end

    def flushed_synchronously?
      @flushed_synchronously == true
    end

    def telemetry_flushed?
      @telemetry_flushed == true
    end
  end
end
