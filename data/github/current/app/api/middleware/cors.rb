# typed: true
# frozen_string_literal: true

# CORS = Cross-Origin Resource Sharing
# http://www.nczonline.net/blog/2010/05/25/cross-domain-ajax-with-cross-origin-resource-sharing/
# http://www.w3.org/TR/cors
# http://code.google.com/p/html5security/wiki/CrossOriginRequestSecurity
class Api::Middleware::Cors
  include GitHub::ServiceMapping

  X_ORIGIN        = "HTTP_X_ORIGIN".freeze
  REQUEST_METHOD  = "REQUEST_METHOD".freeze
  OPTIONS         = "OPTIONS".freeze
  ALLOW_ORIGIN    = "Access-Control-Allow-Origin".freeze
  DEFAULT_ORIGIN  = "*".freeze
  CORS            = {
    "Access-Control-Expose-Headers" => "ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset",
  }.freeze
  PREFLIGHT_CORS  = CORS.dup.update(
    "Access-Control-Max-Age" => "86400",
    "Access-Control-Allow-Headers" => %w[
      Authorization
      Content-Type
      If-Match
      If-Modified-Since
      If-None-Match
      If-Unmodified-Since
      Accept-Encoding
      X-GitHub-OTP
      X-Requested-With
      User-Agent
      GraphQL-Features
      X-Github-Next-Global-ID
      X-GitHub-Api-Version
    ].join(", "),
    "Access-Control-Allow-Methods" =>
      "GET, POST, PATCH, PUT, DELETE",
  ).freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    if env[REQUEST_METHOD] == OPTIONS # is a CORS preflight request?
      push_service_mapping_context(env: env)
      return [204, valid_cors_headers(PREFLIGHT_CORS), []]
    end

    if cors = valid_cors_headers(CORS)
      status, headers, body = @app.call(env)
      cors.each do |key, value|
        headers[key] ||= value
      end
      [status, headers, body]
    else
      @app.call(env)
    end
  end

  def valid_cors_headers(headers)
    headers.merge(ALLOW_ORIGIN => DEFAULT_ORIGIN)
  end
end
