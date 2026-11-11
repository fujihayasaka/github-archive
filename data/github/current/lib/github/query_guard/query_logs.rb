# typed: true
# frozen_string_literal: true

require "base64"
require "zstd-ruby"

module GitHub
  module QueryGuard
    module QueryLogs

      # Number of stack frames to skip to exclude internal framework/wrapper methods.
      BACKTRACE_SKIP_FRAMES = 4

      def self.backtrace_compressed
        root = "#{Rails.root.realpath}/"
        locations = T.must(caller_locations(BACKTRACE_SKIP_FRAMES)).filter_map do |loc|
          path = loc.path.to_s
          next unless path.start_with?(root)

          relative = path.delete_prefix(root)
          next unless relative.match?(/^(app|lib|packages|test)/)
          next if relative.start_with?("test/test_helpers")

          [relative, loc.label, loc.lineno]
        end

        return if locations.empty?

        GitHub::JSON
          .encode(locations)
          .then { |json| Zstd.compress(json) }
          .then { |compressed| Base64.strict_encode64(compressed) }
      rescue StandardError
        nil
      end

      def self.apply!
        ActiveRecord::QueryLogs.taggings = ActiveRecord::QueryLogs.taggings.merge(
          cluster: -> (context) {
            context[:connection]&.pool&.db_config&.name || "unknown"
          },
          run_inside_test: -> {
            Thread.current[:run_inside_test]
          },
          test_name: -> {
            Thread.current[:running_test_name]
          },
          backtrace: -> {
            backtrace_compressed
          }
        )

        Rails.application.configure do
          T.bind(self, Rails::Application)

          config.active_record.query_log_tags += [:run_inside_test, :test_name, :cluster]

          if TestEnv.test_query_guard_tracking_queries?
            # Disable caching of query comments to ensure correct backtraces
            config.active_record.cache_query_log_tags = false
            config.active_record.query_log_tags += [:backtrace]
          end

        end
      end
    end
  end
end
