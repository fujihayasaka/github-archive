# typed: true
# frozen_string_literal: true

require "shed"

class Api::Middleware::LoadShedding
  # {NGINXDelta} reads the `X-Nginx-Request-Start` header of form `t={timestamp}`
  # where `{timestamp}` is a nanosecond granularity UNIX timestamp.
  #
  # `X-Nginx-Request-Start` represents the time at which a request arrived at our
  # pod, any large descrepancy between that timestamp and the current time at
  # which the request reached our rack application is indicative of queue time.
  #
  # This class reports that difference, in order to be used by
  # {Shed::RackMiddleware::Propagate} to adjust any published timeout/deadline.
  #
  # This is set via the following config in NGINX:
  # `proxy_set_header X-Nginx-Request-Start "t=${msec}000";`
  class NGINXDelta
    HEADER = "HTTP_X_NGINX_REQUEST_START"

    def self.call(env)
      request_start_raw = env[HEADER].to_s

      # Header was not set
      return 0 if request_start_raw.empty?

      request_start_sec_timestamp = request_start_raw.delete_prefix("t=").to_f

      # Header is malformed
      return 0 unless request_start_sec_timestamp.positive?

      start_ms = (request_start_sec_timestamp * 1000.0).to_i
      now_ms = (Time.now.to_f * 1000).to_i
      delta = now_ms - start_ms

      [0, delta].max
    end
  end

  # {TimeoutApp} is called when the deadline for the request has been
  # exceeded.
  class TimeoutApp
    def self.call(_env)
      [
        503,
        { "Content-Type" => "text/plain" },
        ["The server is currently unable to handle this request due to a temporary overload.\n"]
      ]
    end
  end

  TRAFFIC_TWIRP = "twirp"
  TRAFFIC_GRAPHQL = "graphql"
  TRAFFIC_API_INTERNAL = "api_internal"
  TRAFFIC_OTHER = "other"

  def initialize(app)
    @app = app
    @shed = Shed::RackMiddleware::Propagate.new(
      app,
      on_timeout: TimeoutApp,
      delta: NGINXDelta
    )
  end

  # {call} will call the wrapped `Shed::RackMiddleware::Propagate`
  # middleware and ensure metrics are sent to Datadog.
  def call(env)
    status, headers, body = _call(env)

    [status, headers, body]
  ensure
    GitHub.dogstats.increment("api.internal.loadshedding", tags: datadog_tags_from_env(env, status))
  end

  private

  def _call(env)
    status, headers, body = @shed.call(env)
    [status, headers, body]
  end

  def datadog_tags_from_env(env, status)
    timeout_set = (!!env["HTTP_X_CLIENT_TIMEOUT_MS"]).to_s
    traffic = traffic_type(env)

    [
      "status:#{status}",
      "timeout_set:#{timeout_set}",
      "client_name:#{client_name(traffic, env)}",
      "operation:#{operation(traffic, env)}",
      "traffic:#{traffic}",
    ]
  end

  def operation(traffic, env)
    if traffic == TRAFFIC_GRAPHQL
      env["github.graphql.operation_name"] || "unknown"
    else
      env["github.api.route"] || "unknown"
    end
  end

  def client_name(traffic, env)
    client_name = "unknown"

    if traffic == TRAFFIC_TWIRP && (hmac = env["HTTP_REQUEST_HMAC"])
      hmac_status, client_key = Api::Internal::Twirp.verify_request_hmac(hmac)
      if hmac_status == :success
        client_name = GitHub.api_internal_twirp_hmac_settings.fetch(client_key, "unknown")
      end
    end

    if traffic == TRAFFIC_API_INTERNAL
      client_name = env[:internal_client_id] || "unknown"
    end

    if traffic == TRAFFIC_GRAPHQL
      client_name = env["github.graphql.client_name"] || "unknown"
    end

    client_name
  end

  def traffic_type(env)
    path_info = env[Rack::PATH_INFO]

    if path_info =~ Api::Internal::Twirp::PATH_REGEX
      TRAFFIC_TWIRP
    elsif path_info =~ Api::GraphQL::PATH_REGEX
      TRAFFIC_GRAPHQL
    elsif path_info =~ Api::Internal::PATH_REGEX
      TRAFFIC_API_INTERNAL
    else
      TRAFFIC_OTHER
    end
  end
end
