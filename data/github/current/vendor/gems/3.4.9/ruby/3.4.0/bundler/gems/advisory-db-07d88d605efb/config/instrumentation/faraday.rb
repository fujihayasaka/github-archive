# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("references_check.faraday") do |_, starts, ends, _, env|
  GitHub::Telemetry::Logs.logger.info(
    "References check faraday stats",
    "http.method": env[:method].to_s.upcase,
    "url.full": env[:url],
    "gh.duration_ms": ((ends - starts) * 1000.0).round(1),
  )
end
