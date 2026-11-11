# typed: true
# frozen_string_literal: true

class GitHub::Authentication::SignedAuthToken::Version1 < GitHub::Authentication::SignedAuthToken
  HMAC_LENGTH = 40

  # Regex that generated tokens should match.
  #
  # Returns a Regexp instance.
  def self.token_regex
    /\A\d+__[-_=a-zA-Z0-9]+--[a-z0-9]{#{HMAC_LENGTH}}\z/
  end

  # Generate a token string from the given options. The data used to generate
  # the token is signed but not encrypted. Don't put sensitive data in the
  # `data` field.
  #
  # user:    - The User to make the token for.
  # scope:   - The String scope the token is valid for.
  # expires: - The Time the token will expire (default 30 seconds from now).
  # data:    - Arbitrary data to store in the token (any basic type).
  #
  # Returns String token.
  def self.generate(user:, scope:, expires: DEFAULT_EXPIRES.from_now, data: nil)
    payload = { scope: scope, expires: expires.to_i, data: data }
    signed_payload = verifier(user).generate(payload)
    "#{user.id}__#{signed_payload}"
  end

  # Verify a token.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  # stafftools_only_ignore_suspension - only used for other token versions.
  #
  # Returns SignedAuthToken instance.
  def self.verify(token:, scope:, stafftools_only_ignore_suspension: false)
    id, token = token.split "__", 2
    return bad_token(:bad_token) if id.blank? || token.blank?
    return bad_token(:bad_token) if id =~ /[^\d]/
    return bad_token(:bad_login) unless user = User.find_by(id: id.to_i)


    hash = begin
      verifier(user).verify(token)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      # In v1 we can differentiate between a bad signature and a bad scope, but
      # we still return :bad_scope to be consistent with the other versions.
      return bad_token(:bad_scope)
    end

    return bad_token(:bad_scope) unless hash["scope"] == scope
    return bad_token(:user_suspended) if user.suspended?
    return bad_token(:expired)   unless hash["expires"] > Time.now.to_i

    new(user: user, expires: Time.at(hash["expires"]), scope: hash["scope"], data: hash["data"], reason: :valid)
  end

  # The version of SignedAuthToken.
  #
  # Returns an Symbol.
  def version
    :"1"
  end

  # A UrlSafeMessageVerifier instance used for signing/verifying tokens.
  #
  # Returns a UrlSafeMessageVerifier instance.
  def self.verifier(user)
    SecurityUtils::UrlSafeMessageVerifier.new user.signed_auth_token_secret, serializer: JSON
  end
end
