# typed: true
# frozen_string_literal: true

# Pushes a lightweight `remote_call_source_datadog_tags` value onto GitHub.context
# very early in the API middleware stack so that DB queries issued before the
# request reaches a Sinatra controller (e.g. during auth fingerprinting, rate
# limiting, database selection, permission caching) get attribution instead of
# `source:N/A`.
#
# Must be installed AFTER Api::Middleware::RouteFinder so that
# `env["github.api.route"]` is populated.
#
# Once Api::App#initialize_context runs, it pushes a more specific
# `remote_call_source_datadog_tags` (with controller/action) onto the same
# GitHub.context stack; that more specific value wins for subsequent lookups
# while the request is being processed by the controller.
class Api::Middleware::EarlyRemoteCallSource
  UNKNOWN_ROUTE = "unknown"

  def initialize(app)
    @app = app
  end

  def call(env)
    method = env["REQUEST_METHOD"].to_s.downcase
    route_path = route_path_from(env)

    tags = [
      "source_type:request",
      "method:#{method}",
      "source:request-#{method}-api_middleware-#{route_path}",
    ]

    GitHub.context.push(remote_call_source_datadog_tags: tags) do
      @app.call(env)
    end
  end

  private

  # `Api::Middleware::RouteFinder` populates `env["github.api.route"]` with values
  # like `"GET /repos/:owner/:repo"`. Strip the leading method to get just the
  # parameterized path; fall back to UNKNOWN_ROUTE when no route matched.
  def route_path_from(env)
    raw = env["github.api.route"].to_s
    return UNKNOWN_ROUTE if raw.empty?

    _method, path = raw.split(" ", 2)
    path && !path.empty? ? path : UNKNOWN_ROUTE
  end
end
