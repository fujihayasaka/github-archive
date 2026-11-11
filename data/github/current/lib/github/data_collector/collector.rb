# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class Collector
      include ActiveSupport::Callbacks

      define_callbacks :reset

      def self.get_instance(name = collector_name)
        collectors = GitHub::DataCollector.collectors
        if collector = collectors[name]
          return collector
        end

        collector = new
        collector.enable if GitHub::DataCollector.enable_by_default?

        collectors[name] = collector
      end

      def self.collector_name; end

      def self.attributes(*attrs)
        attrs.each do |sym|
          class_eval(<<-EOS, __FILE__, __LINE__ + 1)
            def #{sym}=(value)
              self[:#{sym}] = value if enabled?
            end
          EOS

          class_eval(<<-EOS, __FILE__, __LINE__ + 1)
            def #{sym}
              self[:#{sym}]
            end
          EOS
        end
      end

      def initialize
        @enabled = false
        @data = {}

        reset
      end

      def enable
        @enabled = true
      end

      def disable
        @enabled = false
      end

      def enabled=(value)
        @enabled = value
      end

      def enabled?
        @enabled
      end

      def [](key)
        @data[key]
      end

      def []=(key, value)
        @data[key] = value
      end

      def reset
        prev_enabled = enabled?

        enable
        run_callbacks :reset do
          @data = {}
        end

        @enabled = prev_enabled
      end
    end
  end
end
