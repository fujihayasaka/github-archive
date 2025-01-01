# typed: false
# frozen_string_literal: true

# Ensures that batching is enabled and logs the request.
class GitHub::HydroMiddleware
  include Scientist

  SCHEMA = "github.v1.Request"
  TOPIC = SCHEMA
  CONTEXT = :hydro_context
  PAYLOAD = :hydro_payload

  def self.timer
    ::Timer
  end

  def self.rescue_instrumentation_errors?
    Rails.env.production?
  end

  # Public: Extract hydro payload info from the env and publish.
  def self.record_request(env)
    result = GitHub.hydro_request_analytics_publisher.publish(env[PAYLOAD],
      schema: SCHEMA,
    )

    if !result.success?
      handle_error(
        error: result.error,
        stat: "hydro_client.publish_error",
        tags: ["schema:#{SCHEMA}", "error:#{result.error.class.name.underscore}"],
      )
    end
  rescue Encoding::UndefinedConversionError => e
    handle_error(error: e, stat: "hydro_client.encode_error", tags: ["schema:#{SCHEMA}"])
  rescue Hydro::Protobuf::InvalidValueError => e
    handle_error(error: e, stat: "hydro_client.invalid_value_error", tags: ["schema:#{SCHEMA}"])
  rescue => e # rubocop:todo Lint/GenericRescue
    handle_error(error: e, stat: "hydro_client.error", tags: ["schema:#{SCHEMA}", "error:#{e.class.name.underscore}"])
  end

  def self.handle_error(error:, stat:, tags:)
    raise error unless rescue_instrumentation_errors?
    GitHub.dogstats.increment(stat, tags: tags)
    GitHub.report_hydro_error(error)
  end

  def initialize(app)
    @app = app

    @track_mysql = defined?(GitHub::MysqlInstrumenter) && GitHub::MysqlInstrumenter.respond_to?(:query_count)
    @track_gitrpc = defined?(GitRPCLogSubscriber) && GitRPCLogSubscriber.respond_to?(:rpc_count)
    @track_job_stats = defined?(GitHub::JobStats)
  end

  def call(env)
    GitHub.hydro_publisher.start_batch
    GitHub.hydro_request_analytics_publisher.start_batch

    env[CONTEXT] ||= {}

    if GitHub.hydro_enabled?
      env[CONTEXT][:enabled] = true
    end

    begin
      timer = self.class.timer.start

      initialize_hydro_payload(env) if GitHub.hydro_enabled?
    # If anything goes wrong with initializing the hydro request payload, don't
    # let it stop us from handling the request.
    rescue => e # rubocop:todo Lint/GenericRescue
      env[CONTEXT][:enabled] = false
      self.class.handle_error(error: e, stat: "hydro_middleware.error", tags: ["schema:#{SCHEMA}", "error:#{e.class.name.underscore}"])
    end

    status, header, body = @app.call(env)

    begin
      if env[CONTEXT].delete(:enabled)
        finalize_hydro_payload(env, timer, status, header)
        self.class.record_request(env)
      end
    # If anything goes wrong with finalizing the hydro request payload, don't
    # let it stop us from returning [status, header, body]
    rescue => e # rubocop:todo Lint/GenericRescue
      self.class.handle_error(error: e, stat: "hydro_middleware.error", tags: ["schema:#{SCHEMA}", "error:#{e.class.name.underscore}"])
    end

    [status, header, body]
  ensure
    flush_batch
  end

  # Internal: Initialize the hydro payload with any information we know before
  # passing the request down the middleware stack. If the request times out,
  # this is the only payload information that will be populated.
  def initialize_hydro_payload(env)
    env[PAYLOAD] = {
      request_id: env[Rack::RequestId::GITHUB_REQUEST_ID],
      do_not_track_preference: force_encoding(env[GitHub::Middleware::Constants::HTTP_DNT]),
      http_method: http_method_enum(env[GitHub::Middleware::Constants::REQUEST_METHOD]),
      http_accept: force_encoding(env[GitHub::Middleware::Constants::HTTP_ACCEPT] || env["Accept"]),
      http_user_agent: force_encoding(env[GitHub::Middleware::Constants::HTTP_USER_AGENT] || env["User-Agent"]),
      http_referrer: force_encoding(env[GitHub::Middleware::Constants::HTTP_REFERER] || env["Referer"]),
      host: force_encoding(env["SERVER_NAME"]),
      revision: GitHub.current_sha,
      current_ref: GitHub.current_ref,
      timed_out: false,
      pid: Process.pid,
    }

    request = Rack::Request.new(env)

    env[PAYLOAD][:device_cookie] = request.cookies["_device_id"]

    ip = Hydro::IpAddr.new(request.ip)
    env[PAYLOAD].merge!({
      ip_address: ip.to_s,
      ip_version: ip.version || :IP_VERSION_UNKNOWN,
      ip_v4_int: ip.ipv4_int,
      ip_v6_int: ip.ipv6_int,
    })

    location = ip.valid? ? GitHub::Location.look_up(ip.to_s) : {}
    env[PAYLOAD].merge!(location.slice(
      :country_code,
      :country_name,
      :region,
      :region_name,
      :city,
    ))

    if GitHub.kube?
      env[PAYLOAD].merge!({
        kube_cluster: GitHub.kubernetes_cluster_name,
        kube_namespace: GitHub.kubernetes_namespace,
      })
    end

    if track_tenant_context?
      env[PAYLOAD].merge!(GitHub::CurrentTenant.hydro_context)
    end
  end

  # Internal: Finalize the hydro request with information collected during the
  # request.
  def finalize_hydro_payload(env, timer, status, header)
    env[PAYLOAD].merge!({
      mysql_read_only_connection: ActiveRecord::Base.connected_to?(role: :reading),
      http_status: (Integer(status) if status.present?),
      http_content_length: header[GitHub::Middleware::Constants::CONTENT_LENGTH]&.to_i,
      http_content_type: header[GitHub::Middleware::Constants::CONTENT_TYPE],
      elapsed_ms: timer.elapsed_ms,
      cpu_time_ms: timer.elapsed_cpu_ms,
      idle_time_ms: timer.elapsed_idle_ms,
      graphql_accessed_objects: Platform::GlobalScope
        .accessed_objects
        .values
        .map { |graphql_obj| Hydro::EntitySerializer.graphql_accessed_object(graphql_obj) },
      auth_fingerprint: env[Api::Middleware::RequestAuthenticationFingerprint::AUTHENTICATION_FINGERPRINT]&.to_s,
      path: env[GitHub::Middleware::Constants::PATH_INFO],
      catalog_service: env[GitHub::TaggingHelper::PROCESS_SERVICE_KEY] || GitHub::Serviceowners::UNKNOWN_SERVICE,
      alloy_time_ms: (env[GitHub::TaggingHelper::ALLOY_WAIT_TIME] || 0).round
    })

    # the merge of context has to come after the initial merge to ensure
    # any keys set and/or transformed in the app.call(env)
    # overwrite any initial values.
    # i.e. transformations to path:, auth_fingerprint: stay intact.
    env[PAYLOAD].merge!(env[CONTEXT])

    # Ensure we don't log tokens to hydro.
    if env[PAYLOAD][:api_route] == "/applications/:client_id/tokens/:access_token"
      env[PAYLOAD][:path] = env[PAYLOAD][:path].to_s.sub(/tokens\/.+\z/, "tokens/:access_token")
    end

    # Extract referrer controller and action from the referrer path.
    env[PAYLOAD].merge!(calculate_referrer(env[PAYLOAD][:http_referrer], env[PAYLOAD][:request_category]))

    if track_mysql?
      env[PAYLOAD].merge!({
        mysql_queries: GitHub::MysqlInstrumenter.query_count,
        mysql_time_ms: (GitHub::MysqlInstrumenter.query_time * 1000).round,
      })
    end

    if track_gitrpc?
      env[PAYLOAD].merge!({
        gitrpc_count: GitRPCLogSubscriber.rpc_count,
        gitrpc_time_ms: (GitRPCLogSubscriber.rpc_time * 1000).round,
      })
    end

    if track_job_stats?
      if GitHub::JobStats.enqueued.any?
        env[PAYLOAD].merge!({
          enqueue_time_ms: GitHub::JobStats.enqueue_time_ms,
          enqueue_time_ms_by_backend: GitHub::JobStats.enqueue_time_per_backend_ms.transform_keys(&:to_s),
          jobs_enqueued: GitHub::JobStats.enqueued.transform_keys(&:to_s),
          jobs_enqueued_by_backend: GitHub::JobStats.enqueue_count_per_backend_ms.transform_keys(&:to_s),
        })
      end
    end

    env[PAYLOAD].merge!({
      ja3_hash: env["HTTP_X_SSL_JA3_HASH"],
    })

    # the merge of context has to come after the initial merge to ensure
    # any keys set and/or transformed in the app.call(env)
    # overwrite any initial values.
    # i.e. transformations to path:, auth_fingerprint: stay intact.
    env[PAYLOAD].merge!(FlipperSubscriber.hydro_stats)
    env[PAYLOAD].merge!(VexiSubscriber.hydro_stats)
  end

  def calculate_referrer(http_referrer, request_category)
    if request_category != "ajax"
      return { referrer_controller: "", referrer_action: "" }
    end

    begin
      router_response = Rails.application.routes.recognize_path(http_referrer)
      router_response[:controller] = GitHub::TaggingHelper.formatted_controller(router_response[:controller])
    rescue StandardError => error # rubocop:todo Lint/GenericRescue
      return {
        referrer_controller: "invalid_referrer",
        referrer_action: "invalid_referrer"
      }
    end

    if router_response[:unmatched_route]
      return {
        referrer_controller: "unknown",
        referrer_action: "unknown"
      }
    end

    router_response[:controller] = "pull_requests" if router_response.fetch(:pulls_only, false)
    router_response[:controller] = router_response[:controller].camelize + "Controller"

    {
      referrer_controller: router_response[:controller].presence || "unknown",
      referrer_action: router_response[:action].presence || "unknown"
    }
  end

  def track_mysql?
    @track_mysql
  end

  def track_gitrpc?
    @track_gitrpc
  end

  def track_job_stats?
    @track_job_stats
  end

  def track_tenant_context?
    return false unless GitHub.multi_tenant_enterprise?
    GitHub.flipper[:tenant_on_github_v1_request_hydro_event].enabled?
  end

  def http_method_enum(http_method)
    return :REQUEST_METHOD_UNKNOWN unless http_method.present?

    normalized = http_method&.upcase&.to_sym
    if Hydro::Schemas::Github::V1::Request::RequestMethod.resolve(normalized)
      normalized
    else
      :REQUEST_METHOD_UNKNOWN
    end
  end

  # Force UTF8 for user-supplied HTTP headers
  def force_encoding(value)
    value&.dup&.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end

  def flush_batch
    return unless GitHub.flush_hydro_batches?

    result = GitHub.hydro_publisher.flush_batch

    if result && !result.success?
      self.class.handle_error(
        error: result.error,
        stat: "hydro_client.flush_error",
        tags: ["schema:#{SCHEMA}", "publisher:hydro_publisher"],
      )
    end

    result = GitHub.hydro_request_analytics_publisher.flush_batch

    if result && !result.success?
      self.class.handle_error(
        error: result.error,
        stat: "hydro_client.flush_error",
        tags: ["schema:#{SCHEMA}", "publisher:hydro_request_analytics_publisher"],
      )
    end

  end
end
