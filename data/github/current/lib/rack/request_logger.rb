# typed: true
# frozen_string_literal: true

module Rack
  # Rack::RequestLogger is a drop in replacement for Rack::CommonLogger and is
  # setup to pull relevent information from the env and use GitHub::Logger to
  # get request data into our logging pipeline.
  #
  # This is middleware due to simplicity that comes with putting this here
  # rather than in API and the Rails app seperately. Those two entry points
  # should focus on user data logging rather than request logging.
  class RequestLogger

    APPLICATION_LOG_DATA = "APPLICATION_LOG_DATA".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      began_at = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      env[APPLICATION_LOG_DATA] = GitHub::Logger.empty
      status, headers, body = @app.call(env)
      finished_at = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      elapsed = finished_at - began_at
      headers = Utils::HeaderHash.new(headers)

      # TODO: Remove once this PR is inluded https://github.com/open-telemetry/opentelemetry-ruby-contrib/pull/342
      span = GitHub.current_span

      body = BodyProxy.new(body) do
        correlation_context = {
          "TraceId": span.context.hex_trace_id,
          "SpanId": span.context.hex_span_id,
          "ParentSpanId": span.hex_parent_span_id
        }
        GitHub.logger.tagged(correlation_context) do
          self.class.log(env, status, headers, elapsed)
        end
      end
      [status, headers, body]
    end

    # Ignore logging requests containing `/assets` as the path_info in dev
    def self.asset_path_in_development?(env)
      Rails.env.development? && env["PATH_INFO"] =~ /^\/assets/
    end

    def self.sensitive_params_filter
      @sensitive_params_filter ||= GitHub::ParameterFilter.create
    end

    def self.filter_params(hash)
      return nil if hash.blank?
      sensitive_params_filter.filter(hash)
    end

    # Parses a URL and removes sensitive params.
    def self.url_for_logging(url)
      return "" unless url
      Addressable::URI.parse(url).tap do |parsed|
        parsed.query_values = filter_params(parsed.query_values)
      end.to_s
    rescue Addressable::URI::InvalidURIError
      # This can happen when we run the `referer` header through here -- it could be garbage.
      ""
    end

    # Logs data for a Request using GitHub::Logger.
    #
    # env     - Rack env or Hash.
    # status  - Number HTTP status for the response.
    # elapsed - Float elapsed response time in seconds.
    # data    - Optional hash of additional logging info.
    #
    # Returns nothing.
    def self.log(env, status, header, elapsed, data = {})
      # Silence /assets in Development.
      return if asset_path_in_development? env

      request = ::Rack::Request.new(env)
      # Populated by application.
      app_data = env[APPLICATION_LOG_DATA]
      context = non_semconv_fields(request, status, env, header, elapsed, data)

      request_category = env[GitHub::TaggingHelper::PROCESS_REQUEST_CATEGORY]

      if route = Api::App.route_pattern(env)
        context["route"] = route
      end

      if GitHub.semconv_enabled?
        context.merge!(build_semconv_fields(request, status, env, header, elapsed))
      end

      app_data.merge!(context).merge!(data.stringify_keys)
      GitHub.logger.info(app_data)
    end

    def self.non_semconv_fields(request, status, env, header, elapsed, data)
      gc_info = GitHub::DataCollector::GCStatsCollector.get_instance
      {
        "now"                  => Time.now.iso8601,
        "request_id"           => Rack::RequestId.get(env),
        "datacenter"           => GitHub.datacenter,
        "site"                 => GitHub.server_site,
        "region"               => GitHub.server_region,
        "server_id"            => Rack::ServerId.get(env),
        "remote_address"       => request.ip,
        "request_method"       => request.request_method.downcase,
        # not `host` because it would conflict with syslog:
        "request_host"         => request.host,
        "path_info"            => request.path_info,
        "content_length"       => header["Content-Length"] || 0,
        "content_type"         => header["Content-Type"],
        "user_agent"           => request.user_agent,
        "accept"               => env["HTTP_ACCEPT"],
        "language"             => env["HTTP_ACCEPT_LANGUAGE"],
        "referer"              => url_for_logging(env["HTTP_REFERER"]),
        "x_requested_with"     => env["HTTP_X_REQUESTED_WITH"],
        "status"               => status.to_s[0..3],
        "elapsed"              => elapsed,
        "url"                  => url_for_logging(request.url),
        "request_wait_time"    => env[GitHub::TaggingHelper::REQ_WAIT_TIME],
        "worker_request_count" => GitHub.unicorn_worker_request_count,
        "worker_pid"           => GitHub.unicorn_worker_pid,
        "worker_number"        => GitHub.unicorn_worker_number,
        "request_category"     => env["process.request_category"] || "other",
        "allocations"          => gc_info.allocations,
        "minor_gc_count"       => gc_info.minor_count,
        "major_gc_count"       => gc_info.major_count,
        "ja3_hash"             => env["HTTP_X_SSL_JA3_HASH"],
      }.compact
    end

    def self.build_semconv_fields(request, status, env, header, elapsed)
      fields = semconv_fields(request, status, env, header, elapsed)
      if route = Api::App.route_pattern(env)
        fields["gh.request.api.route"] = route
      end
      fields
    end

    # Returns HTTP OTel SemConv fields per https://github.com/github/github-semantic-conventions/blob/43d3c09f5f9f1a21becd76eef04aa154b818a47b/combined-docs/trace/http.md#status
    #
    # request - the Rack request object
    # status  - Number HTTP status for the response.
    # env     - Rack env or Hash.
    # header  - The request header.
    # elasped - Float elapsed response time in seconds.
    def self.semconv_fields(request, status, env, headers, elapsed)
      {
        "gh.request_id"               => ::Rack::RequestId.get(env),
        "gh.actor.is_robot"           => GitHub.robot?(request.user_agent.to_s),
        "http.host"                   => request.host,
        "http.scheme"                 => request.scheme,
        "http.method"                 => request.request_method.downcase,
        "http.target"                 => request.path_info,
        "http.url"                    => url_for_logging(request.url),
        "http.status_code"            => status.to_s[0..3],
        "http.client_ip"              => request.ip,
        "http.server_name"            => ::Rack::ServerId.get(env),
        "http.request.header.referer" => url_for_logging(env["HTTP_REFERER"]),
      }.merge!(GitHub::Telemetry::SemConv::Rack.request_headers(env, "Accept", "Accept-Language", "X-Requested-With", "User-Agent"))
      .merge!(GitHub::Telemetry::SemConv::Rack.response_headers(headers, "Content-Type", "Content-Length"))
    end
  end
end
