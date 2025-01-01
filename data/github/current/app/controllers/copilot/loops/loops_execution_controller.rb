# typed: true
# frozen_string_literal: true

# A controller that handles executing various requests from Copilot Loops app.
class Copilot::Loops::LoopsExecutionController < ApplicationController
  include GitHub::RateLimitedRequest
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::DefaultRateLimitDependency

  before_action :login_required
  before_action :require_feature_enabled

  allow_verified_fetch only: [:create]

  READ_RATE_LIMIT = 400

  rescue_from ActionController::InvalidAuthenticityToken do |_e|
    T.bind(self, Copilot::Loops::LoopsExecutionController)
    render status: :unprocessable_entity, json: error_response(
      code: "invalidAuthenticityToken",
      message: "The provided authenticity token is invalid."
    )
  end

  rate_limit_requests \
    only: [:create],
    max: :read_rate_limit,  # per minute
    ttl: GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL, # 1.minute
    key: :rate_limit_key,
    at_limit: :render_rate_limited_response

  # Accepts a JSON document URL-encoded in the `body` query param with
  #  - query: String (required) a query id, ideally one
  #    corresponding to a stored graphql query.
  def create
    expires_now
    result = decode_and_run

    return if performed?
    render plain: JSON.generate(result.to_h)
  end

  private

  def require_feature_enabled
    render_404 unless feature_enabled?
  end

  def feature_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :copilot_pipes)
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
      return
    end

    result = execute_query(query)

    result
  rescue JSON::ParserError, Yajl::ParseError
    render status: :unprocessable_entity, json: error_response(code: "invalidJSON", message: "Unable to parse JSON body")
  end

  def execute_query(query)
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

  def rate_limit_key
    "loops_execution_controller:#{T.must(request).method}:#{T.must(current_user).id}"
  end

  def read_rate_limit
    READ_RATE_LIMIT
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
end
