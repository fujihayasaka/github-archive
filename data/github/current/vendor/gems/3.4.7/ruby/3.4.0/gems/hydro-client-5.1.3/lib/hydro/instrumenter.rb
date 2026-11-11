require "active_support/notifications"
require "active_support/isolated_execution_state"

module Hydro
  # Simple reimplementation of ActiveSupport::Notifications. Use this in
  # conjunction with the DatadogReporter to add custom metrics for multiple
  # instances of Hydro::Sink and the underlying ruby-kafka client.
  class Instrumenter
    def initialize
      @notifier = ActiveSupport::Notifications::Fanout.new
      @instrumenter = ActiveSupport::Notifications::Instrumenter.new(@notifier)
    end

    def instrument(name, payload = {})
      if @notifier.listening?(name)
        @instrumenter.instrument(name, payload) { yield payload if block_given? }
      else
        yield payload if block_given?
      end
    end

    def subscribe(pattern = nil, callback = nil, &block)
      @notifier.subscribe(pattern, callback, monotonic: false, &block)
    end
  end

  class NoopInstrumenter
    def instrument(name, payload = {})
      yield payload if block_given?
    end

    def subscribe(*args)
      # no op
    end
  end

  class MemoryInstrumenter < NoopInstrumenter
    attr_accessor :notifications

    def initialize
      @notifications = []
      @subscriptions = Hash.new { |h, k| h[k] = [] }
    end

    def instrument(name, payload = {})
      @notifications << [name, payload]
      start = Time.now
      result = super
      keys = @subscriptions.keys.select { |key| key.match(name) }
      keys.each do |key|
        @subscriptions[key].each do |block|
          block.call(name, start, Time.now, nil, payload)
        end
      end
      result
    end

    def subscribe(name, &block)
      @subscriptions[name] << block
    end
  end

  def self.instrumenter
    @instrumenter ||= begin
      if defined?(ActiveSupport::Notifications)
        ActiveSupport::Notifications
      else
        MemoryInstrumenter.new
      end
    end
  end

  def self.instrumenter=(instrumenter)
    @instrumenter = instrumenter
  end
end
