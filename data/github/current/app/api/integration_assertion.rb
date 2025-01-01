# typed: true
# frozen_string_literal: true

class Api::IntegrationAssertion
  CLOCK_SKEW_LEEWAY = 60.seconds
  MAX_EXPIRATION_WINDOW = 10.minutes

  ERROR_MESSAGES = {
    cannot_decode: "A JSON web token could not be decoded",
    bad_algorithm: "Assertion must be signed using RS256",
    iat_blank: "Missing 'issued at' claim ('iat') in assertion",
    iat_invalid: "'Issued at' claim ('iat') must be an Integer " +
                        "representing the time that the assertion was issued",
    iss_blank: "Missing 'issuer' claim ('iss') in assertion",
    iss_invalid: "'Issuer' claim ('iss') must be an Integer",
    exp_blank: "Missing 'expiration time' claim ('exp') in assertion",
    exp_too_far_out: "'Expiration time' claim ('exp') is too far in the " +
                        "future",
    exp_invalid: "'Expiration time' claim ('exp') must be a numeric " +
                        "value representing the future time at which the " +
                        "assertion expires",
    no_key: "Integration must generate a public key",
    not_found: "Integration not found",
    signature_invalid: "Invalid signature",
    signature_immature: "Not before time 'nbf' has not been reached",
    audience_invalid: "Invalid audience 'aud'",
    subject_invalid: "Invalid subject 'sub'",
    jti_invalid: "Invalid jti or missing 'iat'",
    integration_suspended: "Integration suspended"
  }

  attr_reader :value
  attr_accessor :error

  def initialize(env)
    @value = Api::RequestCredentials.token_from_scheme(env, "bearer")
  end

  def integration
    self.error.nil? ? @integration : nil
  end

  def valid?
    validate_payload
    return false unless self.error.nil?
    verify_payload

    self.error.nil?
  end

  def validate_payload
    self.error = begin
      payload, _ = JWT.decode(value, nil, false)
      JWT::Verify.verify_claims(payload,
        verify_expiration: true,
        verify_not_before: true,
        verify_iat: true,
        verify_iss: true,
        leeway: CLOCK_SKEW_LEEWAY,
      )

      if payload["iat"].blank?
        :iat_blank
      elsif payload["iss"].blank?
        :iss_blank
      elsif !valid_issuer?(payload["iss"])
        :iss_invalid
      elsif payload["exp"].blank?
        :exp_blank
      elsif !numberish?(payload["exp"])
        :exp_invalid
      elsif payload["exp"].to_i > MAX_EXPIRATION_WINDOW.from_now.to_i
        :exp_too_far_out
      end
    rescue JWT::InvalidIatError
      :iat_invalid
    rescue JWT::InvalidIssuerError
      :iss_invalid
    rescue JWT::ExpiredSignature
      :exp_invalid
    rescue JWT::VerificationError
      :signature_invalid
    rescue JWT::ImmatureSignature
      :signature_immature
    rescue JWT::InvalidAudError
      :audience_invalid
    rescue JWT::InvalidSubError
      :subject_invalid
    rescue JWT::InvalidJtiError
      :jti_invalid
    rescue JWT::DecodeError
      :cannot_decode
    rescue NoMethodError
      if !numberish?(payload["exp"])
        :exp_invalid
      else
        raise
      end
    end

    return if self.error.present?

    begin
      @integration = find_integration!(payload["iss"])
    rescue ActiveRecord::RecordNotFound
      self.error = :not_found
    end
  end

  def verify_payload
    if integration.public_keys.empty?
      self.error = :no_key
      return
    end

    if integration.suspended?
      self.error = :integration_suspended
      return
    end

    # try to decode & verify the JWT with each public key until one succeeds
    integration.public_keys.each do |pk|
      decoded = decode(value, pk.public_key)
      # verified payload, return immediately
      return if decoded.present?
    end

    # otherwise, we cannot decode the JWT
    self.error = :cannot_decode
  rescue JWT::IncorrectAlgorithm
    self.error = :bad_algorithm
  rescue JWT::DecodeError
    self.error = :cannot_decode
  end

  DECODE_PAYLOAD = {
    algorithm: "RS256",
    leeway: CLOCK_SKEW_LEEWAY,
  }.freeze

  # Internal: Attempt to decode a JWT value with the given OpenSSL::PKey::RSA.
  #
  # Returns successfully decoded payload [{},{}].
  # Returns nil if decoding raised an JWT::DecodeError.
  # Raises JWT::IncorrectAlgorithm (reraise).
  def decode(val, pk)
    JWT.decode(val, pk, true, DECODE_PAYLOAD)
  rescue JWT::IncorrectAlgorithm
    raise
  rescue JWT::DecodeError
  end

  def error_message
    ERROR_MESSAGES[error]
  end

  def valid_issuer?(value)
    numberish?(value) || (
      value.is_a?(String) && OauthAccess::ClientId.client_id?(value, application_klass: Integration)
    )
  end

  def numberish?(value)
    return true if value.is_a?(Integer)
    return true if value.is_a?(String) && !(value.to_i(10) == 0)
    false
  end

  def find_integration!(id)
    ActiveRecord::Base.connected_to(role: :reading) do
      if !numberish?(id)
        integration = Integration.find_by!(key: id)

        if integration.owner&.feature_enabled?(:jwt_client_id_iss)
          return integration
        else
          self.error = :iss_invalid
          return
        end
      end

      Integration.includes(:public_keys).find(id)
    end
  end
end
