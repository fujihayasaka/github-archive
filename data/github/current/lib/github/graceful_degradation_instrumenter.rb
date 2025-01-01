# typed: true
# frozen_string_literal: true

module GitHub
  module GracefulDegradationInstrumenter
    def self.collector
      GitHub::DataCollector::GracefulDegradationCollector.get_instance
    end

    def self.handled_exceptions
      collector.handled_exceptions
    end

    def self.handled_exceptions=(value)
      collector.handled_exceptions = value
    end

    def self.track_handled_exception(exception)
      collector.handled_exceptions << exception
    end

    def self.unhandled_exception
      collector.unhandled_exception
    end

    def self.unhandled_exception=(value)
      collector.unhandled_exception = value
    end

    def self.reset
      collector.reset
    end
  end
end
