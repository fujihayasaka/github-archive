# typed: true
# frozen_string_literal: true

class GitHub::Authentication::SignedAuthToken::Version2 < GitHub::Authentication::SignedAuthToken
  DIGEST      = OpenSSL::Digest::SHA1 # rubocop:disable GitHub/InsecureHashAlgorithm
  HMAC_LENGTH = DIGEST.new.digest_length
  PACK_FORMAT = "Na#{HMAC_LENGTH}a*"

  # Regex that generated tokens should match.
  #
  # Returns a Regexp instance.
  def self.token_regex
    /\A[-_=a-zA-Z0-9]{44,}\z/
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
  def self.generate(user:, scope:, expires: DEFAULT_EXPIRES.from_now, data:  nil)
    # Sign the data.
    payload = MessagePack.pack([expires.to_i, data])
    secret  = scoped_secret(user, scope)
    hmac    = generate_hmac(secret, payload)

    # Generate the token.
    packed = [user.id, hmac, payload].pack(PACK_FORMAT)
    encode(packed)
  end

  # Verify a token.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  # stafftools_only_ignore_suspension - only used for other token versions.
  #
  # Returns SignedAuthToken instance.
  def self.verify(token:, scope:, stafftools_only_ignore_suspension: false)
    # Unpack the token.
    packed = begin
      decode(token)
    rescue ArgumentError # Invalid Base64
      return bad_token(:bad_token)
    end

    id, hmac, payload = packed.unpack(PACK_FORMAT)
    return bad_token(:bad_token) if id.nil? || hmac.blank? || payload.blank?

    user = User.find_by(id: id)

    return bad_token(:bad_login) if user.nil?

    # Verify the digest.
    secret = scoped_secret(user, scope)
    return bad_token(:bad_scope) unless hmac_valid?(secret, payload, hmac)

    return bad_token(:user_suspended) if user.suspended?

    # Pull apart the payload and verify expiration.
    expires, data = MessagePack.unpack(payload)
    return bad_token(:expired) unless expires > Time.now.to_i

    new(
      user: user,
      expires: Time.at(expires),
      scope: scope,
      data: data,
      reason: :valid,
    )
  end

  # The version of SignedAuthToken.
  #
  # Returns an Symbol.
  def version
    :"2"
  end

  # Generate a signing secret from the user's signed_auth_token_secret and the
  # scope.
  #
  # user  - A User object.
  # scope - The String scope the token is valid for.
  #
  # Returns a String.
  def self.scoped_secret(user, scope)
    "#{user.signed_auth_token_secret} | #{scope}"
  end

  # Sign the payload with the secret using a SHA1 HMAC.
  #
  # secret  - The String signing secret.
  # payload - The String value to sign.
  #
  # Returns a String.
  def self.generate_hmac(secret, payload)
    OpenSSL::HMAC.digest(DIGEST.new, secret, payload)
  end

  # Verify the SHA1 HMAC signature of the payload using the secret.
  #
  # secret  - The String signing secret.
  # payload - The String payload that was signed and should be verified.
  # digest  - The String hmac digest to verify.
  #
  # Returns true if the digest was valid, false otherwise.
  def self.hmac_valid?(secret, payload, digest)
    expected_digest = generate_hmac(secret, payload)
    SecurityUtils.secure_compare(expected_digest, digest)
  end

  # Encode a token as url safe base64.
  #
  # token - A binary String token.
  #
  # Returns an encoded String token.
  def self.encode(token)
    Base64.urlsafe_encode64(token)
  end

  # Decode a token as url safe base64.
  #
  # token - An encoded String token.
  #
  # Returns an binary String token.
  def self.decode(token)
    Base64.urlsafe_decode64(token)
  end
end
