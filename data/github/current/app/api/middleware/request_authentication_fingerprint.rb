# typed: true
# frozen_string_literal: true

# Adds a unique fingerprint to each request env based on authorization
# header, remote IP address, and other attributes.
class Api::Middleware::RequestAuthenticationFingerprint

  AUTHENTICATION_FINGERPRINT = "github.authentication_fingerprint".freeze

  # Public: Fetch the request's authentication fingerprint from the given
  # environment. Assumes that this middleware has already been invoked for the
  # current request.
  #
  # env - Rack env.
  #
  # Returns a String or nil.
  def self.get(env)
    env[AUTHENTICATION_FINGERPRINT]
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    GitHub.tracer.in_span("api.middleware", kind: :internal, attributes: {
      "code.namespace" => "RequestAuthenticationFingerprint"
    }) do |_span|
      fingerprint = Api::RequestAuthenticationFingerprint.from(env)
      env[AUTHENTICATION_FINGERPRINT] = fingerprint
      log_data = env[Rack::RequestLogger::APPLICATION_LOG_DATA] ||= GitHub::Logger.empty
      log_data[:"gh.auth.fingerprint"] = fingerprint.to_s

      @app.call(env)
    end
  end
end
