# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module QueryTracking
      sig { returns(Float) }
      attr_accessor :query_tracking_requests_sample_rate

      def query_tracking_enabled?
        defined?(GitHub::MysqlInstrumenter) && GitHub::MysqlInstrumenter.respond_to?(:queries)
      end

      def should_enqueue_social_experience_instrumentation_job?
        query_tracking_requests_sample_rate > 0 && !GitHub::AppEnvironment.test?
      end

      def query_tracking_skip
        GitHub::AppEnvironment.test? ? [] : [:backtrace, :tags]
      end
    end
  end

  extend Config::QueryTracking
end
