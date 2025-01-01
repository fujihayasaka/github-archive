# typed: true
# frozen_string_literal: true

# Public: A signed authentication token for repository-based authentication,
# supporting scopes and expiration.
#
# Examples
#
#   token = SignedAuthToken.generate :repo    => somerepo,
#                                    :scope   => 'some_scope',
#                                    :expires => 30.seconds.from_now
#   parsed_token = SignedAuthToken.verify :token => token
#                                         :scope => 'some_scope'
#   parsed_token.valid?
#   # => true
#   parsed_token.repo
#   # => somerepo
#
#   expired_token = SignedAuthToken.generate :repo    => somerepo,
#                                            :scope   => 'some_scope',
#                                            :expires => 30.seconds.ago
#   parsed_token = SignedAuthToken.verify :token => expired_token
#                                         :scope => 'some_scope'
#   parsed_token.valid?
#   # => false
#   parsed_token.reason
#   # => :expired
#   parsed_token.expired?
#   # => true
#   parsed_token.repo
#   # => nil
class GitHub::Authentication::GitAuth::SignedAuthToken
  class NoSecretProvided < Exception; end
  class NoRepoProvided  < Exception; end
  class NoScopeProvided < Exception; end

  DIGEST       = OpenSSL::Digest::SHA256
  HMAC_LENGTH  = DIGEST.new.digest_length
  PACK_FORMAT  = "wa#{HMAC_LENGTH}a*"
  PREFIX       = "gitauth-v1-"
  TOKEN_REGEX  = /\A#{PREFIX}[-_a-zA-Z0-9]+\z/

  DEFAULT_EXPIRES = 30.seconds
  MAX_EXPIRES     = 1.day

  attr_accessor :repo, :expires, :scope, :data, :reason

  class << self
    # Private. Used only by tests.
    attr_writer :hmac_keys
  end

  def initialize(repo: nil, expires: nil, scope: nil, data: nil, reason: nil)
    @repo    = repo
    @expires = expires
    @scope   = scope
    @data    = data
    @reason  = reason
  end

  # Public: Generate a token string from the given options. The data used to
  #         generate the token is signed but not encrypted. Don't put sensitive
  #         data in the `data` field.
  #
  # options - Options hash.
  #           :repo    - The repo to make the token for.
  #           :scope   - The scope the token is valid for (can be any basic
  #                      type).
  #           :expires - The time when the token should expire (default 30
  #                      seconds from now).
  #           :data    - Arbitrary data to store in the token (any basic type).
  #
  # Returns string token.
  def self.generate(options)
    # Ensure that we aren't caching signed auth tokens.
    GitHub::CacheLeakDetector.no_caching!

    repo    = options[:repo]
    scope   = options[:scope]
    data    = options[:data]
    expires = options.fetch(:expires, DEFAULT_EXPIRES.from_now).to_i

    raise NoRepoProvided  unless repo
    raise NoScopeProvided unless scope
    raise ArgumentError   unless scope.is_a?(String) && scope.present?
    raise ArgumentError   unless expires <= MAX_EXPIRES.from_now.to_i

    # Sign the data.
    payload = MessagePack.pack([expires, data])
    secret  = scoped_secret(hmac_keys.first, repo.id, scope)
    hmac    = generate_hmac(secret, payload)

    # Generate the token.
    packed = [repo.id, hmac, payload].pack(PACK_FORMAT)
    PREFIX + encode(packed)
  end

  # Public: Verify a token string.
  #
  # options - Options hash.
  #           :token - The token string to verify.
  #           :scope - The expected scope of the token.
  #           :repo  - (optional) The expected repo to verify; if missing, any
  #                    repo is accepted.
  #
  # Returns SignedAuthToken instance.
  def self.verify(options)
    token = options[:token]
    scope = options[:scope]

    raise NoScopeProvided unless scope
    raise ArgumentError   unless scope.is_a?(String) && scope.present?
    return bad_token(:bad_token) if token.blank? || !token.start_with?(PREFIX)

    # Strip the prefix from the beginning.
    token = token.sub(PREFIX, "")

    # Unpack the token.
    packed = decode(token)
    id, hmac, payload = packed.unpack(PACK_FORMAT)
    return bad_token(:bad_token) if id.nil? || hmac.blank? || payload.blank?

    # Verify the digest.
    match = hmac_keys.any? do |key|
      secret = scoped_secret(key, id, scope)
      hmac_valid?(secret, payload, hmac)
    end
    return bad_token(:bad_mac) unless match

    repo = Repository.find_by(id: id)
    return bad_token(:bad_repo) unless repo
    return bad_token(:bad_repo) if options[:repo] && repo != options[:repo]

    # Pull apart the payload and verify expiration.
    expires, data = MessagePack.unpack(payload)
    return bad_token(:expired) unless expires > Time.now.to_i

    new(repo: repo, expires: Time.at(expires), scope: scope, data: data, reason: :valid)
  rescue ArgumentError # Invalid Base64
    instrument bad_token(:bad_token)
  end

  # Public: Helpers for identifying the reason why a token is valid or invalid.
  #
  # Each method returns a bool.
  %w[bad_token bad_mac bad_repo expired valid].each do |name|
    define_method("#{name}?") { @reason == name.intern }
  end

  def self.hmac_keys
    return @hmac_keys if defined?(@hmac_keys)
    keys = GitHub.gitauth_token_hmac_keys.select(&:present?)
    raise NoSecretProvided if keys.empty?
    @hmac_keys = keys
  end
  private_class_method :hmac_keys

  # Private: Generate a signing secret from the repository owner's
  # signed_auth_token_secret, the repository ID, and the scope.
  #
  # repo_id  - The Integer ID of a Repository.
  # scope    - The String scope the token is valid for.
  #
  # Returns a String.
  def self.scoped_secret(key, repo_id, scope)
    "#{key} | #{repo_id} | #{scope}"
  end
  private_class_method :scoped_secret

  # Private: Sign the payload with the secret using a SHA256 HMAC.
  #
  # secret  - The String signing secret.
  # payload - The String value to sign.
  #
  # Returns a String.
  def self.generate_hmac(secret, payload)
    OpenSSL::HMAC.digest(DIGEST.new, secret, payload)
  end
  private_class_method :generate_hmac

  # Private: Verify the SHA256 HMAC signature of the payload using the secret.
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
  private_class_method :hmac_valid?

  # Public: Checks whether string is in the format of a SignedAuthToken
  #
  # Returns boolean based on validity.
  def self.valid_format?(token)
    token =~ TOKEN_REGEX
  end

  # Encode a token as hex or url safe base64.
  #
  # token - A binary String token.
  #
  # Returns an encoded String token.
  def self.encode(token)
    Base64.urlsafe_encode64(token, padding: false)
  end
  private_class_method :encode

  # Decode a token as hex or url safe base64.
  #
  # token - An encoded String token.
  #
  # Returns an binary String token.
  def self.decode(token)
    Base64.urlsafe_decode64(token)
  end
  private_class_method :decode

  # Private: Instrument the result of verifying a token.
  #
  # token - A SignedAuthToken instance.
  #
  # Returns the token.
  def self.instrument(token)
    GitHub.dogstats.increment("authentication.gitauth_signed_auth_token", tags: [
      "valid:#{token.valid?}",
      "reason:#{token.reason}",
    ])

    token
  end
  private_class_method :instrument

  def self.bad_token(reason)
    new(reason: reason)
  end
  private_class_method :bad_token

  # Returns the authenticated user for this token or nil, if this token is not
  # for a user or the user is not valid.  If a user is returned, the member will
  # be of the form user:id:login.
  def user
    return nil unless member && member[0] == "user"
    User.find_by(id: member[1])
  end

  # Returns the authenticated deploy key for this token or nil, if this token is
  # not for a deploy key or the deploy key is not valid.  If a public key is
  # returned, the member will be of the form repo:id:nwo and the data will
  # contain a deploy_key attributes.
  def public_key
    return nil unless member && member[0] == "repo"
    return nil unless member[1] == repo.id
    return nil unless key_id = data["deploy_key"]&.to_i
    key = PublicKey.find_by(id: key_id)
    return nil unless key&.repository == repo
    key
  end

  # Returns the type of the member (usually, "user" or "repo") and the member's
  # ID, or nil if the member is not retrievable in this format.
  def member
    return nil unless data.is_a?(Hash)
    return @member if defined?(@member)
    @member = self.class.member(data["member"])
  end

  # Returns the Installation id from the token data.
  #
  # Returns a Integer or nil.
  def installation_id
    data["installation_id"] if data.is_a?(Hash)
  end

  # Returns the Installation type from the token data.
  #
  # Returns a String or nil.
  def installation_type
    data["installation_type"] if data.is_a?(Hash)
  end

  # Returns the type of the member (usually, "user" or "repo") and the member's
  # ID, or nil if the member is not retrievable in this format.
  def self.member(member)
    member = member&.split(":")
    return nil if member.nil?
    [member[0], member[1].to_i]
  end
end
