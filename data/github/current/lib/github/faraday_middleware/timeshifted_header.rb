# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that sets the X-GitHub-Authnd-Test-Time header
    # dynamically on each request when Timecop is active.
    class TimeshiftedHeader < ::Faraday::Middleware
      AUTHND_TEST_TIME_HEADER = "X-GitHub-Authnd-Test-Time"

      def call(env)
        # Add time header during testing to support time travel scenarios
        if GitHub::AppEnvironment.test?
          env.request_headers[AUTHND_TEST_TIME_HEADER] = Time.now.to_i.to_s
        end

        @app.call(env)
      end
    end
  end
end
