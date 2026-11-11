# frozen_string_literal: true

require "datadog/statsd"
require "naught"
require "resolv"

module AdvisoryDB
  module Config
    module Stats
      def stats
        @stats ||= stats_enabled? ? dogstats : nullstats
      end

      def stats_enabled?
        Rails.env.production?
      end

      def dogtags(payload)
        payload.filter_map { |k, v| v.nil? ? nil : "#{k}:#{v}" }
      end

      private

      def dogstats
        Datadog::Statsd.new(
          dogstatsd_host,
          dogstatsd_port,
          namespace: "advisory_db",
          tags: dogtags(application: "advisory-db", role: AdvisoryDB.role),
        )
      end

      def dogstatsd_host
        Resolv.getaddress(ENV.fetch("DOGSTATSD_HOST", nil) || "127.0.0.1").freeze
      end

      def dogstatsd_port
        ENV.fetch("DOGSTATSD_PORT", nil)&.to_i || 28125
      end

      def nullstats
        Naught.build do |config|
          config.mimic(Datadog::Statsd)

          # rubocop:disable Lint/NestedMethodDefinition
          def time(_stat, _opts = {})
            yield
          end
          # rubocop:enable Lint/NestedMethodDefinition
        end.get
      end
    end

    include Stats
  end
end
