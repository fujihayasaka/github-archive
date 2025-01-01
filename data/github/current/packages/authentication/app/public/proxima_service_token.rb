# typed: strict
# frozen_string_literal: true

# Signed JWT tokens which represent a stamp-bound, first-party service in Proxima.  Used to enable increased rate limits
# and attribution for unauthenticate requests.  Each token is (optionally) backed by a ProximaServiceIdentity which
# may encode an increased rate limit per stamp-bound service.
#
# [CAVEATS]
# - These tokens are intended to be used by internal services at GitHub and are not intended to be displayed to users
# - They are not authentication credentials.
# - They do not represent proof of user identity for the purposes of normal authentication and authorization.
# - They are only accepted for unauthenticated requests to api.github.com.

# Proxima services issuing these tokens _must_ include the following JWT claims:
#  iat          - the issued at time
#  exp          - the expiration time (max 6 hrs after iat)
#  aud          - the audience (api.github.com)
#  stamp        - the Proxima stamp name from which the request originates
#  service_name - the first-part service making the request
#  tenant_shortcode  - the shortcode of the Tenant on whose behalf the request is being made
class ProximaServiceToken
  extend T::Helpers
  extend T::Sig

  DEFAULT_DURATION = T.let(1.hour, ActiveSupport::Duration)
  MAX_DURATION = T.let(6.hours, ActiveSupport::Duration)

  TenantNotFoundException = Class.new(StandardError)

  sig { returns(T.nilable(ProximaServiceIdentity)) }; attr_accessor :identity
  sig { returns(T.nilable(String)) }; attr_accessor :stamp
  sig { returns(T.nilable(Symbol)) }; attr_accessor :reason

  sig do
    params(
      identity: T.nilable(ProximaServiceIdentity),
      stamp: T.nilable(String),
      reason: T.nilable(Symbol),
    ).void
  end
  def initialize(identity: nil, stamp: nil, reason: :valid)
    @identity = identity
    @stamp = stamp
    @reason = reason
  end

  sig { returns(T::Boolean) }
  def valid?
    @reason == :valid
  end

  sig { returns(T::Boolean) }
  def failed?
    !valid?
  end

  sig do
    params(
      stamp: String,
      tenant_shortcode: String,
      service_name: String,
      duration: ActiveSupport::Duration,
      secret: T.nilable(String),
    ).returns(String)
  end
  def self.generate(stamp:, tenant_shortcode:, service_name:, duration: DEFAULT_DURATION, secret: nil)
    raise ArgumentError.new("bad tenant") if tenant_shortcode.empty?
    raise ArgumentError.new("invalid stamp") unless GitHub::Config::Proxima.valid_stamp?(stamp)
    raise ArgumentError.new("service not registered") unless ProximaServiceIdentity::REGISTERED_SERVICES.include?(service_name)

    raise ArgumentError.new("duration must be positive") if duration.to_i <= 0
    raise ArgumentError.new("duration too long") if duration.to_i > MAX_DURATION.to_i

    secret ||= signing_secret(stamp)

    payload = {
      # standard claims
      iss: "github.com",
      aud: "api.github.com",
      exp: duration.from_now.utc.to_i,
      iat: Time.now.utc.to_i,
      # custom claims
      stamp: stamp,
      tenant_shortcode: tenant_shortcode,
      service_name: service_name,
    }
    JWT.encode(payload, secret, "HS256", { typ: "JWT" })
  end

  # Verify a token.
  sig { params(token: String).returns(ProximaServiceToken) }
  def self.verify(token)
    # first decode the token to derive the originating stamp. Because each stamp has a unique signing
    # secret, we need it to verify the token.
    unverified, _ = begin
      JWT.decode(token, nil, false)
    rescue JWT::DecodeError
      return new(reason: :bad_token)
    end

    stamp = unverified["stamp"]
    return new(reason: :missing_stamp) if stamp.empty?
    return new(reason: :bad_stamp) unless GitHub::Config::Proxima.valid_stamp?(stamp)

    # verify the token signature
    verified, _ = begin
      JWT.decode(token, signing_secret(stamp), true, {
        algorithm: "HS256",
        aud: "api.github.com",
        verify_aud: true,
      })
    rescue JWT::DecodeError
      return new(reason: :bad_token)
    end

    if verified["exp"] - verified["iat"] > MAX_DURATION.to_i
      return new(reason: :token_duration_too_long)
    end

    begin
      new(
        identity: find_identity(
          tenant_shortcode: resolve_shortcode(verified),
          service_name: verified["service_name"],
        ),
        stamp: stamp,
        reason: :valid,
      )
    rescue => e # rubocop:disable Lint/GenericRescue
      new(reason: :failed_reason_unknown)
    end
  end

  # Retrieves the shortcode of the Proxima Tenant based on the identifier in the payload -- tenant_slug and tenant_id are not supported.
  sig { params(payload: T::Hash[String, T.untyped]).returns(String) }
  private_class_method def self.resolve_shortcode(payload)
    if payload["tenant_shortcode"]&.present?
      payload["tenant_shortcode"]
    else
      raise ArgumentError.new("no tenant identifier found in payload")
    end
  end

  sig { params(tenant_shortcode: String, service_name: String).returns(ProximaServiceIdentity) }
  private_class_method def self.find_identity(tenant_shortcode:, service_name:)
    attr = {
      service_name: service_name,
      tenant_shortcode: tenant_shortcode,
    }

    # returns a identity backed by a MySQL record
    identity = ProximaServiceIdentity.where(**attr).first
    return identity if identity

    # returns a stateless identity (i.e. not MySQL-backed)
    identity = ProximaServiceIdentity.new(**attr)
    identity.readonly!
    identity
  end

  sig { params(stamp: String).returns(String) }
  private_class_method def self.signing_secret(stamp)
    key = GitHub.proxima_service_identity_secret_keys[stamp]
    raise "no signing key found for #{stamp}" if key.nil? || key.empty?
    key
  end
end
