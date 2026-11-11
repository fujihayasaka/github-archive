# frozen_string_literal: true

class MetricsFaradayMiddleware < Faraday::Middleware
  def initialize(app, client:)
    super(app)
    @client = client
  end

  def call(request_env)
    start_time = Time.now.in_time_zone
    @app.call(request_env).on_complete do |response_env|
      duration = Time.now.in_time_zone - start_time

      begin
        tags = {
          method: response_env[:method].to_s,
          host: response_env[:url].host,
          code: response_env[:status].to_s,
        }

        @client.timing(
          "http_client_request_duration_seconds",
          duration,
          tags: tags
        )
      rescue StandardError => e
        # Let's be ultra defensive. Metrics should never break the app.
        Rails.logger.error("FaradayMiddleware: #{e}")
      end
    end
  end
end
