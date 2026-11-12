# frozen_string_literal: true

class MetricsMiddleware
  SLOW_REQUEST_THRESHOLD = 1.0 # seconds

  def initialize(app, client:)
    @app = app
    @client = client
  end

  def call(env)
    start_time = Time.now.in_time_zone
    response = @app.call(env)
    duration = Time.now.in_time_zone - start_time

    tags = {
      code: response.first.to_s,
      method: env["REQUEST_METHOD"].downcase,
    }

    tags[:path] = clean_path(env["PATH_INFO"]) unless %w(301 404).include?(tags[:code])

    begin
      @client.timing(
        "http_server_request_duration_seconds",
        duration,
        tags: tags
      )

      log_slow_request(tags) if duration > SLOW_REQUEST_THRESHOLD
    rescue => e # rubocop:disable Style/RescueStandardError
      # Let's be ultra defensive. Metrics should never break the app.
      Rails.logger.error("MetricsMiddleware: #{e}")
    end

    response
  end

  def clean_path(path)
    path.gsub(%r{/\d+/}, "/:id/").gsub(%r{/\d+$}, "/:id")
  end

  private

  def log_slow_request(tags)
    @client.increment(
      "http_server_slow_request",
      tags: tags
    )
  end
end
