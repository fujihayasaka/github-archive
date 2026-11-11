# typed: true
# frozen_string_literal: true

# Middleware to capture the earliest possible timestamp for request timing measurements.
# This should be placed as early as possible in the middleware stack to measure
# the maximum amount of request processing time.
class Api::Middleware::RequestTimer
  def initialize(app)
    @app = app
  end

  def call(env)
    GitHub.tracer.in_span("api.middleware", kind: :internal, attributes: {
      "code.namespace" => "RequestTimer"
    }) do |_span|
      # Capture the earliest possible timestamp for full pipeline timing
      env["gh.request.middleware_start_time"] = GitHub::Dogstats.monotonic_time
      @app.call(env)
    end
  end
end
