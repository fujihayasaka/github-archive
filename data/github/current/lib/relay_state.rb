# typed: true
# frozen_string_literal: true

require "digest"
require "securerandom"

# An abstract class to manage SAML and OIDC request/response relay state.
#
# Provides an opaque token for use as the `RelayState` during `AuthnRequest`
# phase.
#
# It is designed to persist state like the `return_to` URL.
#
# It also verifies the integrity of the relay state by requiring the digest
# be stored in the session and provided at the response consumption phase.
#
class RelayState
  # Making the new methods private since the class is intended to be accessed through
  # initiate and consume methods only
  private_class_method :new

  attr_reader :status, :nonce, :request_id, :data

  DEFAULT_EXPIRY = 65.minutes
  CONSUMED = "CONSUMED"

  def initialize(nonce:, request_id:, persistent_store: nil)
    @nonce            = nonce
    @request_id       = request_id
    @data             = Hash.new
    @persistent_store = persistent_store

    @status =
      if @nonce.present? && @request_id.present?
        :ok
      else
        :invalid
      end
  end

  # Public: Initiate relay state.
  #
  # Takes a data: kwarg to persist, generates a nonce.
  #
  # Returns an instance of the class.
  def self.initiate(request_id:, data: {}, nonce: generate_nonce,
    expires: DEFAULT_EXPIRY.from_now, persistent_store: nil)
    new(request_id: request_id, nonce: nonce, persistent_store: persistent_store).
      initiate(data: data, expires: expires)
  end

  # Public: Consume a nonce and digest to materialize the relay state.
  #
  # Returns an instance of the class.
  def self.consume(request_id:, nonce:, digest:, persistent_store: nil)
    new(request_id: request_id, nonce: nonce, persistent_store: persistent_store).
      consume(digest: digest)
  end

  # Public: Initiate relay state.
  #
  # Stores the encoded data Hash, with an expiry.
  #
  # Returns self.
  def initiate(data: {}, expires: nil)
    return self unless ok?

    @status = :ok
    @data   = data

    persistent_store.set(key, encode(data), expires: expires)

    self
  end

  # Public: Consume the nonce to look up the relay state, verified against
  # the digest.
  #
  # Returns self.
  def consume(digest:)
    return self unless ok?

    @data = decode(fetch_and_mark_as_consumed(key))

    if verify(digest)
      @status = :ok
    else
      @status = :invalid
      @data   = {}
    end

    self
  end

  # Public: Returns true if the status is OK.
  def ok?
    status == :ok
  end

  # Public: Returns true if the status is not OK.
  def invalid?
    !ok?
  end

  # Internal: Get the value from the persistent store then purge it to
  # prevent reuse
  #
  # Returns value from persistent store referred to by key.
  def fetch_and_mark_as_consumed(key)
    data = persistent_store.get(key).value { nil }
    # purge to prevent reuse
    persistent_store.set(key, encode(CONSUMED), expires: DEFAULT_EXPIRY.from_now) if data
    data
  end
  protected :fetch_and_mark_as_consumed

  # Internal: The store used to persist the relay state.
  def persistent_store
    @persistent_store ||= ExternalIdentities::KV
  end
  protected :persistent_store

  # Internal: Encodes the relay state so that it can be saved in the
  # persistent store.
  #
  # Returns a String.
  def encode(data)
    GitHub::JSON.encode(data)
  end
  protected :encode

  # Internal: Decodes the result of fetching the relay state from the
  # persistent store.
  #
  # result: a Result
  #
  # Returns nil or String.
  def decode(result)
    return Hash.new if result.blank?
    GitHub::JSON.decode(result)
  end
  protected :decode

  # Internal: Returns a String key
  def key
    "relay_state:#{nonce}"
  end
  protected :key

  # Internal: Verify the given digest String against the computed digest
  # value.
  #
  def verify(given)
    return true if SAML.mocked[:skip_request_tracking]
    return if data == CONSUMED
    return unless given.present?
    SecurityUtils.secure_compare(given, digest)
  end
  private :verify

  # Internal: Returns a digest String of the state.
  def digest
    @digest ||= begin
      digest = Digest::SHA256.new
      digest << request_id
      digest << nonce
      digest << encode(data)
      digest.to_s
    end
  end

  # Internal: Returns a nonce used for the RelayState parameter.
  #
  # NOTE: SAML 2.0 spec indicates the RelayState should be no more than 80
  # bytes long. A gotcha here is that `urlsafe_base64` will produce more
  # bytes than the bytelength input.
  #
  # See: https://ruby-doc.org/stdlib-2.1.2/libdoc/securerandom/rdoc/SecureRandom.html#method-c-urlsafe_base64
  def self.generate_nonce
    SecureRandom.urlsafe_base64(40)
  end
  private_class_method :generate_nonce
end
