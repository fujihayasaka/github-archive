# typed: true
# frozen_string_literal: true

class Api::Middleware::ConditionalRequestHeader
  SAFE_REQUEST_METHODS = T.let(Set.new(%w[GET HEAD OPTIONS TRACE]), Set)

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless GitHub.flipper[:api_enable_conditional_request_header_middleware].enabled?
    return @app.call(env) if safe_request?(env)

    if blockable = has_blockable_header?(env)
      blocked = GitHub.flipper[:api_enable_conditional_request_header_blocking].enabled?
      emit_metric env, blockable:, blocked: blocked
      return bad_request if blocked
    else
      emit_metric env, blockable:, blocked: false
    end

    @app.call(env)
  end

  private

  def safe_request?(env)
    SAFE_REQUEST_METHODS.include?(env["REQUEST_METHOD"])
  end

  def has_blockable_header?(env)
    env.key?("HTTP_IF_MATCH") ||
    env.key?("HTTP_IF_UNMODIFIED_SINCE")
  end

  def bad_request
    [
      400, {
        "content-type" => "application/json",
      }, [{
        "message" => "Bad Request",
        "documentation_url" => "https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests-if-appropriate",
        "errors" => ["Conditional request headers are not allowed in unsafe requests unless supported by the endpoint"],
        "status" => "400",
      }.to_json]
    ]
  end

  def emit_metric(env, blockable:, blocked:)
    tags = [
      "controller:#{GitHub::TaggingHelper.controller(env)}",
      "action:#{GitHub::TaggingHelper.api_action(GitHub::TaggingHelper.api_route(env))}",
      "method:#{env["REQUEST_METHOD"]}",
      "blockable:#{blockable}",
      "blocked:#{blocked}",
      "if_none_match:#{env.key?("HTTP_IF_NONE_MATCH")}",
      "if_modified_since:#{env.key?("HTTP_IF_MODIFIED_SINCE")}",
      "if_match:#{env.key?("HTTP_IF_MATCH")}",
      "if_unmodified_since:#{env.key?("HTTP_IF_UNMODIFIED_SINCE")}",
      "if_range:#{env.key?("HTTP_IF_RANGE")}"
    ]

    GitHub.dogstats.increment("api.conditional_request_middleware.count", tags: tags)
  end
end
