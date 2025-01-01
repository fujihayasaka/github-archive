# typed: true
# frozen_string_literal: true

module Api::App::ActionsJwtAuthHelper
  include Kernel
  extend T::Helpers
  requires_ancestor { Api::App }

  def issue_jwt(sub)
    payload = {
      # issued at time, 60 seconds in the past to allow for clock drift
      iat: Time.now.to_i - 60,
      # JWT expiration time (60 minute maximum)
      exp: Time.now.to_i + (60 * 60),
      # iss is the url of the stamp that issued the token
      iss: default_iss,
      # aud is the url of the stamp that the token is intended for
      aud: default_aud,
      # sub is the user that the token is for
      sub: sub.to_s,
    }
    JWT.encode(payload, signing_key[:key], "RS256", { kid: signing_key[:kid] })
  end

  def validate_jwt(jwt, expected_iss: GitHub.host_name_with_tenant, expected_aud: GitHub.host_name_with_tenant)
    begin
      jwt_claims, _ = JWT.decode(jwt, nil, true, verification_options(expected_iss, expected_aud)) do |header|
        key_func(header.with_indifferent_access)
      end

      jwt_claims.with_indifferent_access
    rescue JWT::InvalidIatError, JWT::InvalidIssuerError, JWT::ExpiredSignature, JWT::VerificationError, JWT::ImmatureSignature, JWT::InvalidAudError, JWT::InvalidSubError, JWT::InvalidJtiError
      raise
    rescue JWT::DecodeError
      # We may want to check if this request is auth'd another way (not a JWT)
      # So if the string is not a JWT just return nil instead of raising an error
      nil
    end
  end

  def validate_and_find_user_by_jwt(jwt)
    claims = validate_jwt(jwt)
    return nil unless claims

    ActiveRecord::Base.connected_to(role: :reading) { User.find_by(id: claims[:sub]) }
  end

  def attempt_jwt_login
    begin
      user = validate_and_find_user_by_jwt(api_auth.token)
      @current_user = user if user.present? && user.feature_enabled?(:actions_api_can_use_jwt)
    rescue JWT::InvalidIatError, JWT::InvalidIssuerError, JWT::ExpiredSignature, JWT::VerificationError, JWT::ImmatureSignature, JWT::InvalidAudError, JWT::InvalidSubError, JWT::InvalidJtiError
      reject_for_bad_credentials!
    end
  end

  private

  def key_func(header)
    # Find the key that signed the JWT by kid
    key = verification_keys.find { |k| k[:kid] == header[:kid] }
    raise JWT::VerificationError, "No keys found that match the kid" unless key

    key[:key]
  end

  def verification_options(iss, aud)
    {
      verify_expiration: true,
      verify_not_before: true,
      verify_iat: true,
      verify_iss: true,
      verify_aud: true,
      algorithms: ["RS256"],
      iss: iss,
      aud: aud
    }
  end

  def signing_key
    @signing_key ||= GitHub.actions_jwt_signing_key
  end

  def verification_keys
    @verification_keys ||= GitHub.actions_jwt_verification_keys
  end

  def default_iss
    GitHub.host_name_with_tenant
  end

  def default_aud
    GitHub.host_name_with_tenant
  end
end
