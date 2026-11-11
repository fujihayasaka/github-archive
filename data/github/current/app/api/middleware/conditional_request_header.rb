# typed: true
# frozen_string_literal: true

class Api::Middleware::ConditionalRequestHeader
  SAFE_REQUEST_METHODS = T.let(Set.new(%w[GET HEAD OPTIONS TRACE]), Set)

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if safe_request?(env)

    return bad_request if has_blockable_header?(env)

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
end
