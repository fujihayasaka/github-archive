# frozen_string_literal: true

class HMACAuthentication
  # Machines in the same network can have a clock skew
  # that prevents them from ever authenticating correctly
  # to the API server, even with a valid HMAC key on the client.
  # This setting allows us to have a generous 10 minute
  # window within which the clocks can skew between the client & API server.
  REQUEST_HMAC_CLOCK_SKEW = 10.minutes
  REQUEST_HMAC_HEADER = "HTTP_REQUEST_HMAC"
  # We also support X-Request-HMAC for historical reasons.
  LEGACY_REQUEST_HMAC_HEADER = "HTTP_X_REQUEST_HMAC"
  HMAC_TOKEN_DIGEST = OpenSSL::Digest::SHA256
  PATH_INFO = "PATH_INFO"

  # These paths are allowed to skip request hmac validation.
  SKIP_PATHS = [
  "/",
  "/_ping",
  %r(\A/_chatops),
  %r(\A/checkpoints),
  ]

  # Takes the HMAC of an integer epoch timestamp with key.
  def self.request_hmac(time, key)
    timestamp = time.to_i.to_s
    digest = HMAC_TOKEN_DIGEST.new
    hmac = OpenSSL::HMAC.new(key, digest)
    hmac << timestamp
    "#{timestamp}.#{hmac}"
  end

  def initialize(app)
    @app = app
    # Multiple simultaneous keys are supported to allow easy key rotation.
    # The keys are space delimited.
    @dependency_graph_api_hmac_keys = ENV["DEPENDENCY_GRAPH_API_HMAC_KEYS"].to_s.split(" ")
  end

  def call(env)
    # Don't validate tokens for paths in the skip_paths
    skip_validate = skip_path?(env[PATH_INFO])

    # No need to validate if path doesn't return privileged information.
    return @app.call(env) if skip_validate

    # Pass request on if the token is valid.
    if is_valid_hmac_token?(received_hmac: env[LEGACY_REQUEST_HMAC_HEADER]) || is_valid_hmac_token?(received_hmac: env[REQUEST_HMAC_HEADER])
      return @app.call(env)
    end

    # access denied otherwise.
    [401, {}, []]
  end

  # private
  # Determines whether given path is allowed to skip request hmac validation.
  def skip_path?(path)
    SKIP_PATHS.any? { |skip_path| skip_path.match?(path) }
  end
  # Generates a HMAC signature from the pre-configured HMAC Key
  # for the service and validates that the client sent an equivalent value
  # in the REQUEST_HMAC header in the request.
  def is_valid_hmac_token?(received_hmac: "")
    # If there's no HMAC header in the request.
    return false if received_hmac.blank?

    # The HMAC is of the format <timestamp>.<sha256>
    # e.g. 1534188429.e7e00d966524ce8a5088109fa81ab9
    timestamp, hmac = received_hmac.split(".", 2)
    return false if timestamp.blank? || hmac.blank?

    # We only need the integer value going forward.
    timestamp = timestamp.to_i

    # Allow for a bit of clock skew, latency, etc in either direction.
    valid_timestamp =
      timestamp > REQUEST_HMAC_CLOCK_SKEW.ago.to_i &&
      timestamp < REQUEST_HMAC_CLOCK_SKEW.from_now.to_i

    return false unless valid_timestamp

    @dependency_graph_api_hmac_keys.each do |key|
      expected_hmac = self.class.request_hmac(Time.at(timestamp), key)

      # If any of the signatures match, we don't need to validate any more.
      return true if Rack::Utils.secure_compare(
        received_hmac,
        expected_hmac
      )
    end

    return false
  end
end
