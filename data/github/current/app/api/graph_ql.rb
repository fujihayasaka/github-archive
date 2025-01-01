# typed: true
# frozen_string_literal: true

class Api::GraphQL < Api::App
  PATH_REGEX = /\A(?:\/api)?\/graphql\/?\z/i.freeze

  # Don't rate limit the GraphQL API the same way we do for other
  # endpoints as it requires much different logic and is based on query
  # complexity instead of # of calls.
  rate_limit_as nil

  class ExternalIPRequest < StandardError; end
  class InsecureSiteAdminAppAccess < StandardError; end

  before { ensure_user_logged_in! }

  after do
    update_logs_with_rate_limits
    update_hydro_with_rate_limits
    update_logs_with_global_id_selection
    set_request_metadata
    set_rate_limit_headers
  end

  # This endpoint has its own rate limiting scheme, so opt out of the REST API one
  post "/graphql", operation_id: :ignored, skip_rate_limit: true  do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/graphql-platform"
    @graphql_context = build_graphql_context

    response = Platform.execute(
      query,
      target: target,
      context: @graphql_context,
      variables: variables,
      operation_name: operation_name,
      raise_exceptions: false,
      request_env: env
    )

    # Add graphql_errors to the `hydro_context` so they get instrumented in the Request event.
    hydro_context[:graphql_errors] = response.instrumenter.serialized_errors_for_instrumentation

    push_filtered_request_body_to_context(response.scrubbed_query_string) if response.success?

    instrument_gql_events_with_timing(response) if response.success?

    deliver_raw(response, { skip_caching_headers: true })
  end

  get "/graphql", operation_id: :ignored, skip_rate_limit: true do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/graphql-platform"
    @graphql_context = build_graphql_context
    @graphql_context[:mask] = Platform::SchemaRuntimeMask.new(target)


    if medias.api_param?(:idl)
      result = Platform::Schema.to_definition(context: @graphql_context)
      deliver_raw({ data: result })
    else # Platform::Schema.to_json expects and invokes the instrumentation, which requires specific context keys to be set
      result = Platform.execute(
        GraphQL::Introspection::INTROSPECTION_QUERY,
        target: target,
        context: @graphql_context,
        raise_exceptions: false,
        request_env: env
      )
      deliver_raw(result)
    end
  end

  def default_documentation_url
    GitHub.developer_help_url + "/graphql"
  end

  private

  def instrument_gql_events_with_timing(response)
    if GitHub.flipper[:measure_gql_event_instrumentation].enabled?(current_user)
      GitHub.dogstats.distribution_time("graphql.instrument_gql_events") do
        instrument_gql_events(response)
      end
    else
      instrument_gql_events(response)
    end
  end

  def instrument_gql_events(response)
    return unless GitHub.flipper[:audit_log_graphql_events].enabled?
    return if target == :internal || GitHub.enterprise?

    request.body.rewind
    request_body = request.body.read

    audit_event = {
      application_name: @graphql_context[:oauth_app]&.name,
      integration: @graphql_context[:integration]&.name,
      query_string: response.scrubbed_query_string,
      rate_limit_remaining: cost_limiter.rate_limit.remaining,
      request_body: request_body.truncate_bytes(1_000_000, omission: ""),
      request_method: request.request_method,
      route: route_pattern,
      status_code: @graphql_context[:response].status,
      url_path: request.path,
      user: current_user,
      request_access_security_header: request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
    }

    org_ids = response.tracker.accessed_objects.values
      .select { |obj| obj.is_a?(Platform::Objects::Organization) }
      .map(&:database_id)

    businesses_checked = []
    ::Business.joins(:organizations).where(organizations: { id: org_ids }).find_each do |business|
      businesses_checked << business.id
      next unless business.api_request_events_enabled?

      GitHub.instrument("api.request", audit_event.merge({ business: business }))
    end

    repo_ids = response.tracker.accessed_objects.values
      .select { |obj| obj.is_a?(Platform::Objects::Repository) }
      .map(&:database_id)

    repo_ids.each_slice(500) do |batch|
      ::Repository.from_ids(batch).active.private_scope.org_owned.with_organization.find_each do |repo|
        business = repo.organization&.business
        next unless business
        next if businesses_checked.include?(business.id)
        next unless business.api_request_events_enabled?

        GitHub.instrument("api.request", audit_event.merge({ business: repo.business_owner }))
      end
    end
  end

  def ensure_user_logged_in!
    if !logged_in?
      deliver_error! 401, \
                    message: "This endpoint requires you to be authenticated.", \
                    documentation_url: default_documentation_url + "/guides/forming-calls-with-graphql#authenticating-with-graphql"
    end
  end

  def set_request_metadata
    # only set for internal integrations, to reduce cardinality sent to
    # datadog.
    return unless current_integration&.github_owned?

    request.env["github.graphql.client_name"] = current_integration.slug
  end

  def set_rate_limit_headers
    cost_limiter.rate_limit.set_headers(response.headers)
  end

  def update_logs_with_rate_limits
    cost_limiter.rate_limit.update_logs(log_data)
  end

  def update_logs_with_global_id_selection
    log_data.update(
      "gh.graphql.global_id_type": get_global_id_selection.to_s.downcase
    )
  end

  def get_global_id_selection
    if GitHub.multi_tenant_enterprise?
      :NEXT
    else
      platform_context[:global_id_selection][:user_preference] ? :NEXT : :LEGACY
    end
  end

  def update_hydro_with_rate_limits
    cost_limiter.rate_limit.update_hydro(hydro_context)
  end

  def query
    request_params["query"]
  end

  def variables
    request_params["variables"]
  end

  def operation_id
    request_params["operationId"]
  end

  def operation_name
    request_params["operationName"]
  end

  def requested_schema
    request_params["schema"]
  end

  def cost_limiter
    @cost_limiter ||= Platform::CostLimiter.new(
      Api::RateLimitConfiguration.for(Api::RateLimitConfiguration::GRAPHQL_FAMILY, self)
    )
  end

  def service_requesting_internal_schema?
    if request.env["HTTP_GRAPHQL_SCHEMA"] == "internal"
      return false if current_integration && !current_integration.github_owned?

      request_token = request.env["HTTP_GITHUB_INTERNAL_GRAPHQL_TOKEN"]
      valid_token = request_token.present? &&
        GitHub.valid_graphql_service_token?(request_token)
      if valid_token
        return true
      end

      if internal_ip_request?
        # Because of some bug with X-Forwarded-For in the kube proxy layers,
        # internal_ip_request? will return true for public requests to a lab.
        # As a simple fix, only allow internal_ip_requests if we are not on a lab.
        if !GitHub.dynamic_lab?
          return true
        end
      end
    end

    false
  end

  def site_admin_requesting_internal_schema?
    (request.env["HTTP_GRAPHQL_SCHEMA"] == "internal" || requested_schema == "internal") && site_admin?
  end

  def site_admin_pat?
    @oauth && @oauth.personal_access_token? && @graphql_context[:granted_oauth_scopes]&.include?("site_admin")
  end

  def github_oauth_app?
    return false if current_integration
    return false unless current_app

    current_app.owner == GitHub.trusted_oauth_apps_owner
  end

  def site_admin?
    return false unless logged_in?

    if current_user.site_admin? && site_admin_pat?
      return true
    end

    if current_user.site_admin? && github_oauth_app?
      result = scope?(current_user, "site_admin")
      unless result
        if GitHub.flipper[:graphql_strict_site_admin_app_access].enabled?(current_user)
          return false
        else
          # this is the current insecure behavior
          return true
        end
      end
      return result
    end

    false
  end

  def target
    if site_admin_requesting_internal_schema? || service_requesting_internal_schema?
      # Collect data on external callers calling into the internal schema
      if GitHub.remote_ip_restrictions_enabled? && !internal_ip_request?
        err = ExternalIPRequest.new("Internal GraphQL schema request made from an external IP")
        Failbot.report_trace(err)
      end
      :internal
    else
      :public
    end
  end

  def build_graphql_context
    base_context = platform_context

    if (base_context[:viewer].employee? || base_context[:viewer].site_admin?) && request.env["HTTP_GRAPHQL_TRACE"]
      performance_trace = true
      # Add a detailed trace if requested
      if request.env["HTTP_GRAPHQL_TRACE_OBJECTS"]
        performance_trace_field_profile_type = :allocations
        performance_trace_field_profile_path = request.env["HTTP_GRAPHQL_TRACE_OBJECTS"]
      elsif request.env["HTTP_GRAPHQL_TRACE_LINES"]
        performance_trace_field_profile_type = :lines
        performance_trace_field_profile_path = request.env["HTTP_GRAPHQL_TRACE_LINES"]
      else
        performance_trace_field_profile_type = nil
        performance_trace_field_profile_path = nil
      end
    else
      performance_trace = false
      performance_trace_field_profile_type = nil
      performance_trace_field_profile_path = nil
    end

    graphql_global_id_type = get_global_id_selection

    # To more safely read from replicas, we accept the header:
    # PermitReplicas - indicates the client explicitly permits the use of replicas
    # See Platform::Objects::ReadArgumentsFromReplicas for more details.
    client_permits_replicas = request.env["HTTP_X_PERMITREPLICAS"] == "1"

    if GitHub.multi_tenant_enterprise?
      base_context.merge!({
        internal_api_host: !!GitHub::Routers::Api.internal_api_host?(request.host),
        request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
      })
    end

    base_context.merge(
      origin: origin,
      cost_limiter: cost_limiter,
      request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      request_access_security_header: request.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
      # Apply performance tracing if a site admin requests it.
      performance_trace: performance_trace,
      performance_trace_field_profile_type: performance_trace_field_profile_type,
      performance_trace_field_profile_path: performance_trace_field_profile_path,
      graphql_global_id_type: graphql_global_id_type,
      operation_id: operation_id,
      client_permits_replicas: client_permits_replicas
    )
  end

  def request_params
    @request_params ||= receive(Hash, required: false) || {}
  end

  def origin
    :api
  end

  # Push the filtered request body as a Hash into
  # GitHub.context[:filtered_request_body].
  #
  # Returns nothing.
  def push_filtered_request_body_to_context(scrubbed_query)
    # Filter request body if needed and store for later use
    filtered_request_body = {}
    filtered_request_body[:query] = scrubbed_query if scrubbed_query
    filtered_request_body[:operationName] = operation_name if operation_name

    if filtered_request_body.keys.any?
      GitHub.context.push(filtered_request_body: filtered_request_body)
      Audit.context.push(filtered_request_body: filtered_request_body)
    end
  end
end
