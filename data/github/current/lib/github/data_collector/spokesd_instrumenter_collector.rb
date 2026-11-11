# typed: true
# frozen_string_literal: true

module GitHub
  module DataCollector
    class SpokesdInstrumenterCollector < Collector
      CallStats = Struct.new(:count, :time)

      set_callback :reset, :after do |collector|
        collector.rpc_count = 0
        collector.rpc_time = 0
        collector.rpc_call_stats = Hash.new { |h, k| h[k] = CallStats.new(0, 0) }
      end

      attributes :rpc_count, :rpc_time, :rpc_call_stats

      def self.collector_name
        :spokesd_instrumenter_collector
      end

      def self.with_track
        prev_enabled = self.get_instance.enabled?
        self.get_instance.enable
        yield
      ensure
        self.get_instance.enabled = prev_enabled
      end

      class FaradayMiddleware < Faraday::Middleware
        def initialize(app)
          super(app)
        end

        def call(env)
          return @app.call(env) unless SpokesdInstrumenterCollector.get_instance.enabled?

          start = Time.now
          begin
            @app.call(env)
          ensure
            duration_ms = (Time.now - start) * 1000

            # Only collect per-endpoint stats in tests
            if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
              url_components = env[:url].path.split("/").reject(&:empty?)
              endpoint = if url_components.first == "twirp"
                # Format: /twirp/<API>/<endpoint>
                url_components.third&.to_sym || :unknown
              elsif url_components.first == "streaming"
                # Format: /streaming/<version>/<endpoint+args>
                if url_components.fifth == "blobs"
                  # /streaming/<version>/(repositories|gists)/<repoID>/blobs/<oid>
                  :GetBlobContentsStreaming
                else
                  # /streaming/<version>/<endpoint>
                  url_components.third&.capitalize&.concat("Streaming")&.to_sym || :unknown
                end
              else
                :unknown
              end

              stats = SpokesdInstrumenterCollector.get_instance.rpc_call_stats[endpoint]
              stats.time += duration_ms
              stats.count += 1
            end

            SpokesdInstrumenterCollector.get_instance.rpc_count += 1
            SpokesdInstrumenterCollector.get_instance.rpc_time += duration_ms
          end
        end
      end
    end
  end
end
