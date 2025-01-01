# typed: true
# frozen_string_literal: true

class GitHub::Authentication::SignedAuthToken::Session < GitHub::Authentication::SignedAuthToken
  # big endian uint32 | any length binary string
  PAYLOAD_PACK_FORMAT = "Na*"

  #  big endian uint64 | 10 byte binary string | any length binary string
  TOKEN_PACK_FORMAT   = "Q>a10a*"

  # We store timestamps in a uint32. These tokens won't work past 2106
  MAX_TIME = Time.at(2**32 - 1)

  # A prefix that isn't included in the base32 charset, used as a differentiator
  # between versions. This isn't signed and isn't a guarantee of the version,
  # just a hint.
  VERSION_IDENTIFIER = "GHSAT0"

  # Regex that generated tokens should match.
  #
  # Returns a Regexp instance.
  def self.token_regex
    /\A#{VERSION_IDENTIFIER}[#{GitHub::Base32::DEFAULT_CHARSET}]{36,}\z/i
  end

  # Generate a token string from the given options. The data used to generate
  # the token is signed but not encrypted. Don't put sensitive data in the
  # `data` field.
  #
  # session: - The UserSession to make the token for.
  # scope:   - The String scope the token is valid for.
  # expires: - The Time the token will expire (default MAX_TIME).
  # data:    - Arbitrary data to store in the token (any basic type).
  #
  # Returns String token.
  def self.generate(session:, scope:, expires: MAX_TIME, data: nil)
    raise ArgumentError if expires > MAX_TIME

    packed_data = data.nil? ? "" : MessagePack.pack(data)
    payload = [expires.to_i, packed_data].pack(PAYLOAD_PACK_FORMAT)

    secret = scoped_secret(session, scope)
    hmac = generate_hmac(secret, payload)
    packed = [session.id, hmac, payload].pack(TOKEN_PACK_FORMAT)

    VERSION_IDENTIFIER + GitHub::Base32.encode(packed)
  end

  # Verify a token.
  #
  # token: - The String token to verify.
  # scope: - The expected String scope of the token.
  # stafftools_only_ignore_suspension - only used for other token versions.
  #
  # Returns SignedAuthToken instance.
  def self.verify(token:, scope:, stafftools_only_ignore_suspension: false)
    b32 = token.upcase.delete_prefix(VERSION_IDENTIFIER)

    decoded = begin
      GitHub::Base32.decode(b32)
    rescue ArgumentError
      return bad_token(:bad_token)
    end

    id, hmac, payload = decoded.unpack(TOKEN_PACK_FORMAT)
    return bad_token(:bad_token) if id.nil? || hmac.empty? || payload.empty?

    session = UserSession.joins(:user).find_by(id: id)

    # "bad_login" doesn't make a ton of sense in this context, but it's useful
    # for consistency with old versions where this was returned if the user was
    # misssing.
    return bad_token(:bad_login) if session.nil?

    return bad_token(:session_expired) if session.expired?
    return bad_token(:session_revoked) if session.revoked?
    return bad_token(:session_inactive) unless session.active?
    return bad_token(:user_suspended) if T.must(session.user).suspended?

    secret = scoped_secret(session, scope)

    unless SecurityUtils.secure_compare(hmac, generate_hmac(secret, payload))
      return bad_token(:bad_scope)
    end

    expires, packed_data = payload.unpack(PAYLOAD_PACK_FORMAT)
    return bad_token(:expired) unless expires > Time.now.to_i
    data = packed_data == "" ? nil : MessagePack.unpack(packed_data)

    new(
      user: session.user,
      session: session,
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
    :session
  end

  # Generate a signing secret from the user's signed_auth_token_secret, the
  # scope and the user session id.
  #
  # session - The UserSession to make the token for.
  # scope   - The String scope the token is valid for.
  #
  # Returns a String.
  def self.scoped_secret(session, scope)
    "#{session.user.signed_auth_token_secret} | #{session.id} | #{scope}"
  end

  # Sign the payload with the secret using a SHA1 HMAC.
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
