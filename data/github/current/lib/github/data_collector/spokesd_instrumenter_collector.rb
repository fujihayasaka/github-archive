# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class SpokesdInstrumenterCollector < Collector
      set_callback :reset, :after do |collector|
        collector.rpc_count = 0
        collector.rpc_time = 0
      end

      attributes :rpc_count, :rpc_time

      def self.collector_name
        :spokesd_instrumenter_collector
      end

      class FaradayMiddleware < Faraday::Middleware
        def initialize(app)
          super(app)
        end

        def call(env)
          return @app.call(env) unless ::FeatureFlag.vexi.enabled?(:spokesd_instrumenter_collector, default: false)
          return @app.call(env) unless SpokesdInstrumenterCollector.get_instance.enabled?

          start = Time.now
          begin
            @app.call(env)
          ensure
            duration_ms = (Time.now - start) * 1000
            SpokesdInstrumenterCollector.get_instance.rpc_count += 1
            SpokesdInstrumenterCollector.get_instance.rpc_time += duration_ms
          end
        end
      end
    end
  end
end
