# typed: true
# frozen_string_literal: true

class GitHub::Authentication::SignedAuthToken::Version3 < GitHub::Authentication::SignedAuthToken
  # big endian uint32 | any length binary string
  PAYLOAD_PACK_FORMAT = "Na*"

  #  big endian uint32 | 10 byte binary string | any length binary string
  TOKEN_PACK_FORMAT   = "Na10a*"

  # We store timestamps in a uint32. These tokens won't work past 2106
  MAX_TIME = Time.at(2**32 - 1)

  # Regex that generated tokens should match.
  #
  # Returns a Regexp instance.
  def self.token_regex
    /\A[#{GitHub::Base32::DEFAULT_CHARSET}]{29,}\z/i
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
    raise ArgumentError if expires > MAX_TIME

    packed_data = data.nil? ? "" : MessagePack.pack(data)
    payload = [expires.to_i, packed_data].pack(PAYLOAD_PACK_FORMAT)

    secret = scoped_secret(user, scope)
    hmac = generate_hmac(secret, payload)
    packed = [user.id, hmac, payload].pack(TOKEN_PACK_FORMAT)

    GitHub::Base32.encode(packed)
  end

  # Verify a token.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  # stafftools_only_ignore_suspension - if true, the token will return valid even if the corresponding user account is suspended. Only used as stafftools bypass for account recovery analysis (`verify_for_stafftools`).
  #
  # Returns SignedAuthToken instance.
  def self.verify(token:, scope:, stafftools_only_ignore_suspension: false)
    decoded = begin
      GitHub::Base32.decode(token.upcase)
    rescue ArgumentError
      return bad_token(:bad_token)
    end

    id, hmac, payload = decoded.unpack(TOKEN_PACK_FORMAT)
    return bad_token(:bad_token) if id.nil? || hmac.empty? || payload.empty?

    user = User.find_by(id: id)
    return bad_token(:bad_login) if user.nil?

    secret = scoped_secret(user, scope)

    unless SecurityUtils.secure_compare(hmac, generate_hmac(secret, payload))
      return bad_token(:bad_scope)
    end

    return bad_token(:user_suspended) if !stafftools_only_ignore_suspension && user.suspended?

    expires, packed_data = payload.unpack(PAYLOAD_PACK_FORMAT)
    return bad_token(:expired) unless expires > Time.now.to_i
    data = packed_data == "" ? nil : MessagePack.unpack(packed_data)

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
    :"3"
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

  # Sign the payload with the secret using a SHA256 HMAC.
  #
  # secret  - The String signing secret.
  # payload - The String value to sign.
  #
  # Returns a 16 charascter base32 encoded String.
  def self.generate_hmac(secret, payload)
    full = OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, secret, payload)

    # RFC2104 recommends not using less than half the digest and not using less
    # than 80 bits. We could use half of a SHA1 and be in accordance with this,
    # but 80 bits of SHA256 seems preferrable, given SHA1's weaknesses.
    full[0...10]
  end
end
