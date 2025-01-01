# typed: true
# frozen_string_literal: true

# A controller that serves the internal graphql schema for use as a frontend
# API. This uses cookie auth and is only intended for use by github-controlled
# javascript. To limit abuse it is rate limited, implements verified-fetch CSRF
# protection and can only execute queries that have already been defined within
# our persisted query store.
class InternalGraphqlController < ApplicationController
  include IssuesSubscriptionsHelper
  include InternalGraphqlTracingHelper
  include SubIssuesReactHelper
  include GitHub::RateLimitedRequest
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::DefaultRateLimitDependency

  before_action :login_required, except: [:show]
  before_action :check_sec_headers, except: [:create]

  allow_verified_fetch only: [:create]

  rescue_from ActionController::InvalidAuthenticityToken do |_e|
    T.bind(self, InternalGraphqlController)
    GitHub.dogstats.increment("internal_graphql_unverified_fetch")
    render status: :unprocessable_entity, json: error_response(
      code: "invalidAuthenticityToken",
      message: "The provided authenticity token is invalid."
    )
  end

  # Depends on all clusters since this serves GraphQL.
  depends_on_clusters \
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Lodge,
    ApplicationRecord::Memex,
    ApplicationRecord::Migrations,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Permissions,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::Stratocaster,
    ApplicationRecord::TokenScanningService,
    only: [:show],
    optional: true

  READ_RATE_LIMIT = 400
  READ_RATE_LIMIT_ANON = 60
  WRITE_RATE_LIMIT = 60

  preload_features [
    :pull_request_single_subscription
  ]

  rate_limit_requests \
    only: [:show],
    max: :read_rate_limit,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :rate_limit_key,
    at_limit: :render_rate_limited_response

  rate_limit_requests \
    only: [:create],
    if: :logged_in?,
    max: WRITE_RATE_LIMIT,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :rate_limit_key,
    at_limit: :render_rate_limited_response

  # Accepts a JSON document URL-encoded in the `body` query param with
  #  - query: String (required) a query id, ideally one
  #    corresponding to a stored graphql query.
  #  - variables: Hash (optional) the variables to bind to
  #    the given graphql query.
  def show
    expires_now
    result = decode_and_run

    return if performed?
    # `render json:` doesn't work with preloading because preload requests
    # don't set an Accept header. Rails produces a 400 response with no content 🤷
    render plain: JSON.generate(result.to_h)
  end

  # Accepts a JSON-encoded POST body with
  #  - query: String (required) a query id, ideally one
  #    corresponding to a stored graphql query.
  #  - variables: Hash (optional) the variables to bind to
  #    the given graphql query.
  def create
    result = decode_and_run

    return if performed?
    render json: result.to_h
  end

  # This overrides the service catalog tagging defined in `service_mapping` to modify the catalog service tagging to properly associate based on the referrer.
  def logical_service # rubocop:todo GitHub/UseRestfulActions
    if T.must(request).referrer.present?
      path = referrer_path

      router_response = Rails.application.routes.recognize_path(path, method: :get)
      controller = GitHub::TaggingHelper.formatted_controller(router_response[:controller])

      return "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/#{IssuesHelper::ISSUES_TAG}" if controller == "issues"
    end

    super
  end

  private

  # override of AuthenticatedSystem#access_denied (called from login_required)
  # We need a version that never redirects and just plain 404s because
  # preloading makes us do do weird format things in this controller.
  def access_denied
    render json: error_response(code: "authenticationError", message: "Couldn’t authenticate you", error_type: "AUTHENTICATION"), status: :not_found
  end

  EXPECTED_SEC_HEADERS = {
    # Ensure the request comes from github.com
    "sec-fetch-site" => "same-origin",
    # Requiring this prevents attacks that rely on tricking a victim to make a
    # GraphQL request by adding an API URL to an image src. The value `empty`
    # will only be present on actual fetch() calls or similar.
    # https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Sec-Fetch-Dest
    "sec-fetch-dest" => "empty"
  }

  def check_sec_headers
    EXPECTED_SEC_HEADERS.each do |header, required_value|
      actual = T.must(request).headers[header]
      if !actual
        # Missing headers are ok, not all browsers support this mechanism
        GitHub.dogstats.increment("request.internal_graphql.missing_header", tags: { header: })
      elsif actual != required_value
        # If the header is present it must be the expected value.
        GitHub.dogstats.increment("request.internal_graphql.invalid_header", tags: { header:, actual: })
        render status: :unprocessable_entity, json: error_response(
          code: "invalidHeader",
          message: "Expected value for header `#{header}` is `#{required_value}`, but received `#{actual}`."
        )
        return
      end
    end
  end

  def extract_payload_from_body
    encoded_payload = T.must(request).raw_post
    GitHub::JSON.parse(encoded_payload)
  end

  memoize def extract_payload_from_uri
    encoded_payload = T.must(request).GET.fetch("body") do
      render status: :unprocessable_entity, json: error_response(code: "malformedRequest", message: "required query param `body` missing")
      return
    end
    GitHub::JSON.parse(encoded_payload)
  end

  def decode_and_run
    payload = if get_method?
      extract_payload_from_uri
    elsif post_method?
      extract_payload_from_body
    else
      raise "unexpected method #{T.must(request).method.inspect}"
    end

    query_id = payload && payload["query"]
    if query_id.nil?
      render status: :unprocessable_entity, json: error_response(code: "malformedRequest", message: "required key `query` missing")
      return
    end

    variables = payload["variables"]
    scope_object = payload["scopeObject"]
    scope = T.must(request).GET.fetch("scope", nil)
    subscription_topic = T.must(request).GET.fetch("subscriptionTopic", nil)

    reporting_tags = []
    controller = nil
    referrer_controller_action = nil
    if T.must(request).referrer.present?
      path = referrer_path
      url_pattern = GitHub.route_query_mapper.get_matching_url_pattern(path)
      reporting_tags << "url_pattern:#{url_pattern[:url]}" if url_pattern.present?

      router_response = Rails.application.routes.recognize_path(path, method: :get)
      controller = GitHub::TaggingHelper.formatted_controller(router_response[:controller])
      referrer_controller_action = "#{controller}##{router_response[:action]}"
      reporting_tags << "referrer_controller_action:#{referrer_controller_action}"
    end

    if subscription_topic
      reporting_tags << "subscription_event:#{parse_subscription_event_from_topic(subscription_topic).underscore}"
    end

    result_object = execute_query(
      operation_id: query_id,
      variables:,
      # The controller name and action from where the request originated
      referrer_controller_action: referrer_controller_action,
      performance_trace: tracing_enabled?,
      scope:,
      reporting_tags:,
      scope_object:,
      subscription_topic:,
      enforce_read_only: get_method?,
      block_mutations: get_method?,
      add_query_time_tags_fn: add_query_time_tags_fn(controller)
    )

    if !result_object.nil?
      result = result_object.to_h
      # Perform secondary work that is related to the result of the query, to be returned in the response
      compute_extra_callbacks(result, query_id)

      add_performance_trace(result, result_object.query.operation_name, result_object.query.query_string, variables, T.must(request).headers["HTTP_X_GITHUB_REQUEST_ID"])

      GitHub.current_span&.set_attribute("graphql.operation.name", result_object.query.operation_name)
    end

    # report the time it took to update the subscription
    dispatch_time = T.must(request).GET.fetch("dispatchTime", nil)&.to_f
    if dispatch_time && subscription_topic && dispatch_time > 0
      dispatch_time_parsed = T.let(Time.at(dispatch_time), Time)
      time_diff = Time.now - dispatch_time_parsed
      elapsed_time_ms = (time_diff * 1000).to_i
      GitHub.dogstats.distribution("graphql_subscriptions.dispatch.time", elapsed_time_ms, tags: ["subscription_event:#{parse_subscription_event_from_topic(subscription_topic).underscore}"])
    end

    result
  rescue JSON::ParserError, Yajl::ParseError
    render status: :unprocessable_entity, json: error_response(code: "invalidJSON", message: "Unable to parse JSON body")
  rescue Platform::Errors::ForbiddenAnonymousQuery => e
    render status: :unauthorized, json: error_response(code: "forbiddenQuery", error_type: "forbiddenQuery", message: e.message)
  rescue Platform::Errors::UnknownQuery => e
    Failbot.report(e)
    render status: :not_found, json: error_response(code: "unknownQuery", error_type: "unknownQuery", message: "No query with given identifier known")
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

  def referrer_path
    return nil unless (request_referrer = T.must(request).referrer).present?
    URI.parse(request_referrer).path
  end

  def get_method?
    T.must(request).method == "GET"
  end

  def post_method?
    T.must(request).method == "POST"
  end

  def parse_subscription_event_from_topic(topic)
    # <scope>:<event>:argName:argValue:argName:argValue
    # ":issueCommentDeleted:comment:IC_kwAPzPc:id:I_kwAPFw"
    split_topic = topic.split(":")
    if split_topic.size > 1
      split_topic[1]
    else
      "unknown"
    end
  end

  def verify_request?
    true
  end

  def allow_forgery_protection
    true
  end

  def rate_limit_key
    if current_user
      "internal_graphql_controller:#{T.must(request).method}:#{T.must(current_user).id}"
    else
      rate_limit_key_by_ip
    end
  end

  def read_rate_limit
    return READ_RATE_LIMIT if logged_in?

    READ_RATE_LIMIT_ANON
  end

  def render_rate_limited_response
    render status: :too_many_requests, json: error_response(
      code: "slowDown", message: "Your browser sent requests too quickly"
    )
  end

  # This returns arbitrary data, no TFCA is possible.
  # Conditional access is enforced by platform resolvers.
  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def add_performance_trace(result, query_name, query_text, variables, request_id = nil)
    return unless tracing_enabled?

    tracer = Platform::GlobalScope.tracers&.find { |t| t.is_a?(Platform::PerformancePaneTracer) }

    if tracer
      extensions_result = Platform::PerformancePaneTracer::ExtensionsResult.new(tracer)
      result[:__trace] = extensions_result.to_h
      result[:__trace][:query_name] = query_name
      result[:__trace][:query_text] = query_text
      result[:__trace][:query_variables] = variables
      result[:__trace][:method] = T.must(request).method
      result[:__trace][:url] = T.must(request).url
      if !request_id.nil?
        result[:__trace][:request_id] = request_id
      end
    end
  end

  def compute_extra_callbacks(result, query_id)
    preload_pull_requests = current_user&.feature_enabled?(:pull_request_single_subscription)

    # TODO: Review and handle REPOSITORY_MILESTONE_PAGE_QUERY subscriptions appropriately.
    query_callback = {
      ISSUE_INDEX_PAGE_QUERY.graphql_query_id => ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issues_index_query(query_id, result, preload_pull_requests:)
      },
      SEARCH_PAGINATED_QUERY.graphql_query_id => ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issues_index_query(query_id, result, preload_pull_requests:)
      },
      ISSUE_VIEWER_VIEW_QUERY.graphql_query_id => ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issue_viewer_query(query_id, result)
      },
      ISSUE_DASHBOARD_KNOWN_VIEW_PAGE_QUERY.graphql_query_id => ->(query_id, result) {
        IssuesSubscriptionsHelper.compute_subscriptions_for_issues_dashboard_query(query_id, result, preload_pull_requests:)
      }
    }

    if query_callback.key?(query_id)
      callback = query_callback[query_id]
      result[:extensions] ||= {}
      result[:extensions][:subscriptions] = callback.call(query_id, result)
    end
  end

  def add_query_time_tags_fn(controller)
    if controller == "issues"
      get_sub_issues_add_query_time_tags_fn
    else
      nil
    end
  end
end
