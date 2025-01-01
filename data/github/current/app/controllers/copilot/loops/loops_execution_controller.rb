# typed: true
# frozen_string_literal: true

# A controller that handles executing various GraphQL from Copilot Loops app.
class Copilot::Loops::LoopsExecutionController < ApplicationController
  include ApplicationController::VerifiedFetchDependency

  class GraphQLAPIError < StandardError
    attr_reader :status, :response_body

    def initialize(message, status = nil, response_body = nil)
      super(message)
      @status = status
      @response_body = response_body
    end
  end

  class GraphQLExecutionError < StandardError
    attr_reader :original_error

    def initialize(message, original_error = nil)
      super(message)
      @original_error = original_error
    end
  end

  before_action :login_required
  before_action :require_feature_enabled

  allow_verified_fetch only: [:create]

  rescue_from ActionController::InvalidAuthenticityToken do |_e|
    T.bind(self, Copilot::Loops::LoopsExecutionController)
    render status: :unprocessable_entity, json: error_response(
      code: "invalidAuthenticityToken",
      message: "The provided authenticity token is invalid."
    )
  end

  rescue_from Loops::QueryParser::OperationNotAllowedError do |e|
    T.bind(self, Copilot::Loops::LoopsExecutionController)
    render status: :unprocessable_entity, json: error_response(
      code: "operationNotAllowed",
      message: e.message
    )
  end

  # Accepts a JSON document URL-encoded in the `body` query param with
  #  - query: String (required) a query id, ideally one
  #    corresponding to a stored graphql query.
  def create
    expires_now
    result, reauth_resources = decode_and_run

    return if performed?

    result_hash = result.respond_to?(:to_h) ? result.to_h : result

    response = {
      "data" => result_hash["data"]
    }

    # Combine main result resources with reauth resources
    main_resources = extract_resource_data(result) || []
    all_resources = main_resources + (reauth_resources || [])
    unique_resources = all_resources.uniq { |resource| resource["id"] }

    if unique_resources.any?
      response["resources"] = unique_resources
    end

    if result_hash["errors"]
      response["errors"] = result_hash["errors"]
    end

    render plain: JSON.generate(response)
  end

  private

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_pipes)
  end

  def use_public_api_with_token?
    feature_enabled_globally_or_for_user?(feature_name: :loops_public_graphql_api)
  end

  def build_reauth_query?
    feature_enabled_globally_or_for_user?(feature_name: :loops_graphql_reauth_query)
  end

  # override of AuthenticatedSystem#access_denied (called from login_required)
  def access_denied
    render json: error_response(code: "authenticationError", message: "Couldn’t authenticate you", error_type: "AUTHENTICATION"), status: :not_found
  end

  def decode_and_run
    payload = if post_method?
      extract_payload_from_body
    else
      raise "unexpected method #{T.must(request).method.inspect}"
    end

    query = payload && payload["query"]
    if query.nil?
      render status: :unprocessable_entity, json: error_response(code: "malformedRequest", message: "required key `query` missing")
      return [nil, nil]
    end

    if use_public_api_with_token?
      query_parser = Loops::QueryParser.new(query)
      reauth_query = query_parser.parse(build_reauth_query: build_reauth_query?)

      if auth_token
        # Execute main query and re-auth query in parallel using ConcurrentFaraday
        connection = create_concurrent_faraday_connection(num_threads: 2)

        main_promise = T.let(nil, T.nilable(ConcurrentFaraday::Promise[T.untyped]))
        reauth_promise = T.let(nil, T.nilable(ConcurrentFaraday::Promise[T.untyped]))

        connection.in_parallel do
          main_promise = execute_graphql_with_token_concurrent(
            connection, query, "GitHub-Copilot-Loops", raise_on_error: true
          )

          if build_reauth_query? && reauth_query
            reauth_promise = execute_graphql_with_token_concurrent(
              connection, reauth_query, "GitHub-Copilot-Loops-Reauth", raise_on_error: false
            )
          end
        end

        result = T.must(main_promise).sync  # Use sync instead of value to raise exceptions
        reauth_result = reauth_promise&.sync

        # Extract reauth resources if available
        reauth_resources = reauth_result ? extract_reauth_resource_data(reauth_result) : nil

        [result, reauth_resources]
      else
        render status: :unprocessable_entity, json: error_response(code: "missingAuthToken", message: "Copilot auth token is required")
        [nil, nil]
      end
    else
      result = execute_query_internal(query)
      [result, nil]
    end
  rescue JSON::ParserError, Yajl::ParseError
    render status: :unprocessable_entity, json: error_response(code: "invalidJSON", message: "Unable to parse JSON body")
    [nil, nil]
  rescue GraphQLAPIError => e
    render status: :unprocessable_entity, json: error_response(code: "graphqlAPIError", message: e.message)
    [nil, nil]
  rescue GraphQLExecutionError => e
    render status: :unprocessable_entity, json: error_response(code: "graphqlExecutionError", message: e.message)
    [nil, nil]
  end

  def execute_query_internal(query)
    origin = Platform::ORIGIN_API

    context = {
      viewer: current_user,
      session: T.unsafe(self).session,
      user_session: T.unsafe(self).user_session,
      rails_request: request,
      enforce_conditional_access_via_graphql: true,
      request_access_security_header: request&.env[EnterpriseManagedUsersHelper::ENTERPRISE_ACCESS_HEADER],
      origin: origin,
      is_relay_request: true,
      controller: T.unsafe(self).controller_name,
      action: T.unsafe(self).action_name,
      cap_filter: T.unsafe(self).cap_filter,
      authenticated_actor_using_web_session: true,
    }

    Platform.execute(
      query,
      target: :public,
      variables: [],
      context: context,
      raise_exceptions: true,
      request_env: request&.env,
      validate: true,
      enforce_read_only: true,
      block_mutations: true,
    )
  end

  def create_concurrent_faraday_connection(num_threads: 2)
    ConcurrentFaraday.new(GitHub.graphql_api_url, num_threads: num_threads) do |conn|
      conn.headers["Content-Type"] = "application/json"
      conn.headers["Authorization"] = auth_token.authorization_header_value
      conn.options[:timeout] = 10
      conn.response :json
      conn.adapter :concurrent_adapter
    end
  end

  def execute_graphql_with_token_concurrent(connection, query, user_agent, raise_on_error: true)
    connection.headers["User-Agent"] = user_agent

    response_promise = connection.post("/graphql") do |req|
      req.body = { query: query }.to_json
    end

    # Transform the promise to handle our specific error handling logic
    response_promise.then do |response|
      if response.success?
        response.body
      else
        if raise_on_error
          raise GraphQLAPIError.new(
            "GraphQL API request failed with status #{response.status}",
            response.status,
            response.body
          )
        else
          log_reauth_failure("HTTP error", response.status, response.body, query)
          nil
        end
      end
    end.rescue do |error|
      if raise_on_error
        # Always wrap in GraphQLExecutionError for consistency with sequential version
        raise GraphQLExecutionError.new("Failed to execute GraphQL query with token: #{error.message}", error)
      else
        log_reauth_failure("Exception", nil, error.message, query, error)
        nil
      end
    end
  end

  def execute_graphql_with_token(query, client_name, user_agent, raise_on_error: true)
    conn = GitHub::FaradayClient.internal(client_name, url: GitHub.graphql_api_url) do |builder|
      builder.headers["Content-Type"] = "application/json"
      builder.headers["Authorization"] = auth_token.authorization_header_value
      builder.headers["User-Agent"] = user_agent
    end

    request_body = { query: query }
    post_body = request_body.to_json
    response = conn.post("/graphql", post_body)

    if response.success?
      JSON.parse(response.body)
    else
      if raise_on_error
        raise GraphQLAPIError.new(
          "GraphQL API request failed with status #{response.status}",
          response.status,
          response.body
        )
      else
        log_reauth_failure("HTTP error", response.status, response.body, query)
        nil
      end
    end
  end

  def extract_reauth_resource_data(reauth_result)
    return [] unless reauth_result && reauth_result["data"]

    resources = []
    extract_resources_from_data(reauth_result["data"], resources)

    resources.uniq { |resource| resource["id"] }
  end

  def extract_resources_from_data(data, resources)
    case data
    when Hash
      if data["id"]
        resources << {
          "type" => data["__typename"] || "unknown",
          "id" => data["id"]
        }
      end
      data.each_value { |value| extract_resources_from_data(value, resources) }
    when Array
      data.each { |item| extract_resources_from_data(item, resources) }
    end
  end

  def log_reauth_failure(failure_type, status, error_message, reauth_query, exception = nil)
    log_data = {
      event: "loops_reauth_query_failure",
      failure_type: failure_type,
      error_message: error_message,
    }

    if status
      log_data["gh.http_status"] = status
    end

    if exception
      log_data["exception.type"] = exception.class.name
      log_data["exception.message"] = exception.message
    end

    log_data["gh.query"] = reauth_query

    GitHub.logger.info("Loops re-auth query failed", log_data)
  end

  def auth_token
    GitHub.decode_and_decrypt_capi_token(request&.headers[CopilotAPI::TOKEN_HEADER])
  rescue => e
    raise GraphQLExecutionError.new("Failed to decrypt Copilot auth token: #{e.message}", e)
  end

  def simple_box
    T.must_because(GitHub.dotcom_capi_simple_box) { "must have an encryption key set" }
  end

  def error_response(code:, message:, error_type: "INTERNAL")
    JSON.generate(
      "errors" => [{
        "type" => error_type,
        "message" => message,
        "extensions" => {
          "code" => code
        }
      }],
      "data" => {}
    )
  end

  def extract_payload_from_body
    encoded_payload = T.must(request).raw_post
    GitHub::JSON.parse(encoded_payload)
  end

  def post_method?
    T.must(request).method == "POST"
  end

  def verify_request?
    true
  end

  def allow_forgery_protection
    true
  end

  # This returns arbitrary data from the GraphQL API, no TFCA is possible.
  # Conditional access is enforced by platform resolvers.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def extract_resource_data(result)
    return nil unless result.respond_to?(:tracker) && result.tracker&.accessed_objects

    result.tracker.accessed_objects.values.map do |graphql_object|
      {
        "type" => graphql_object.class.graphql_name,
        "id" => graphql_object.object.global_relay_id
      }
    end
  end
end
