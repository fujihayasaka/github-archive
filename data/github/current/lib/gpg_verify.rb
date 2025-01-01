# typed: false
# frozen_string_literal: true

Mime::Type.register "application/x-msgpack", :msgpack
Mime::Type.register "application/pgp-keys", :pgp_keys
Mime::Type.register "application/pgp-signature", :pgp_signature
Mime::Type.register_alias "application/pgp-keys", :gpg

class GpgVerify
  CACHE_BASE_KEY   = "gpgverify_cache"
  CACHE_VERSION    = "2"
  CACHE_DIGEST     = OpenSSL::Digest::SHA256
  CACHE_TTL        = 1.day
  REQUEST_TIMEOUT  = 2.5

  attr_reader :connection

  def initialize(url)
    @connection = Faraday.new(url) do |conn|
      conn.use GitHub::FaradayMiddleware::RequestID
      conn.adapter :persistent_excon
    end
  end

  # Parse metadata from public keys.
  #
  # public_keys - Array of Binary String public keys.
  #
  # Returns an Array of Hashes of metadata.
  def decode_public_keys(public_keys)
    return [] if public_keys.empty?

    cache_multi(:decode_public_keys, public_keys) do |misses|
      service_circuit_breaker do
        request(:decode_public_keys, body: misses)
      end
    end
  end

  # Parse the issuer key-ids from signatures.
  #
  # signatures - Array of binary String signatures.
  #
  # Returns an Array of binary String key-ids.
  def signature_issuer_key_ids(signatures)
    return [] if signatures.empty?

    cache_multi(:signature_issuer_key_ids, signatures) do |misses|
      service_circuit_breaker do
        request(:signature_issuer_key_ids, body: misses)
      end
    end
  end

  # Verify a message signature using the given public key.
  #
  # message            - Binary String message whose signature to verify.
  # signature          - Binary String signature to verify.
  # public_key         - Binary String public key to verify signature with.
  #
  # Returns true if the signature was made over the message using the public
  # key, false otherwise.
  def verify(message, signature, public_key)
    results = batch_verify([{
      signature: signature,
      message:   message,
      key_id:    "key1",
      public_key: public_key,
      id:         "message1",
    }])

    results["message1"] == VALID
  end

  # Possible states returned by #batch_verify
  VALID = "valid"
  INVALID = "invalid"

  # Verify a collection of signatures/messages.
  #
  # requests - An Array of Hashes of signatures/messages to be verified.
  #           :signature  - The ASCII armored signature String.
  #           :message    - The String message that was signed.
  #           :key_id     - The binary String key-id of the signing key.
  #           :public_key - The public key for verifying the signature.
  #           :id         - A unique String ID for identifying this signature/
  #                         message pair.
  #
  # Returns a Hash of results. Eg:
  #   {"id1": "valid", "id2": "invalid", "id3": "valid"}
  def batch_verify(requests)
    return {} if requests.empty?

    results = cache_multi(:batch_verify, requests) do |misses|
      batch_verify_uncached(misses)
    end

    results.to_h
  end

  # Verify a collection of signatures/messages without caching.
  #
  # requests - An Array of Hashes of signatures/messages to be verified.
  #           :signature  - The ASCII armored signature String.
  #           :message    - The String message that was signed.
  #           :key_id     - The binary String key-id of the signing key.
  #           :public_key - The public key for verifying the signature.
  #           :id         - A unique String ID for identifying this signature/
  #                         message pair.
  #
  # Returns an Array of [id, result] Arrays. Eg:
  #   [["id1", "valid"], ["id2", "invalid"], ["id3": "valid"]]
  # The ordering of the returned array matches the ordering of the requests.
  def batch_verify_uncached(requests)
    body = { keys: {}, signatures: {} }

    requests.each do |req|
      key_id = req[:key_id]
      body[:keys][key_id] = req[:public_key]
      body[:signatures][req[:id]] = {
        key: key_id,
        signature: req[:signature],
        data: req[:message],
      }
    end

    results = service_circuit_breaker do
      request(:batch_verify, body: body)
    end

    # Preserve ordering from params.
    requests.map do |req|
      id = req[:id]
      [id, results[id]]
    end
  end

  # Get gpgverify's signing key.
  #
  # Returns a String armored PGP key.
  def signing_key
    GitHub.cache.fetch(cache_key(:signing_key), ttl: 5.minutes) do
      service_circuit_breaker do
        request(:signing_key)
      end
    end
  end

  # Sign the message with gpgverify's signing key.
  #
  # message - The String message to sign.
  #
  # Returns a String armored PGP signature.
  def sign(message, time: nil)
    signing_circuit_breaker do
      request(:sign, body: message, time: time)
    end
  end

  # Get the version of the gpgverify server that is running.
  #
  # Returns a String version.
  def version
    pinglish["version"]
  end

  # The process ID of the gpgverify server.
  #
  # Returns an Integer.
  def server_pid
    pinglish["pid"]
  end

  # Data returned by `/_ping` endpoint.
  #
  # Returns a Hash.
  def pinglish
    request(:ping)
  end

  private

  ACCEPT_HEADER       = "Accept"
  CONTENT_TYPE_HEADER = "Content-Type"
  TIME_HEADER         = "X-Git-Commit-Time"

  ROUTES = {
    ping: {
      method: :get,
      path:   "/_ping",
      accept: Mime[:msgpack],
      type:   "ping",
    }.freeze,
    batch_verify: {
      method:       :post,
      path:         "/gpg/signatures/verify",
      content_type: Mime[:msgpack],
      accept:       Mime[:msgpack],
      type:         "batch_verify",
    }.freeze,
    signature_issuer_key_ids: {
      method:       :post,
      path:         "/gpg/signatures/get_key_id",
      content_type: Mime[:msgpack],
      accept:       Mime[:msgpack],
      type:         "signature_issuer_key_ids",
    }.freeze,
    decode_public_keys: {
      method:       :post,
      path:         "/gpg/public_keys/decode",
      content_type: Mime[:msgpack],
      accept:       Mime[:msgpack],
      type:         "decode_public_keys",
    }.freeze,
    signing_key: {
      method: :get,
      path:   "/gpg/signing_key",
      accept: Mime[:pgp_keys],
      type:   "signing_key",
    },
    sign: {
      method:       :post,
      path:         "/gpg/signing_key/sign",
      content_type: Mime[:text],
      accept:       Mime[:pgp_signature],
      time_header:  true,
      type:         "sign",
    },
  }.freeze

  # Make a request to the gpgverify server.
  #
  # type  - Symbol type of request to make (See ROUTES).
  # body: - Request body to send.
  #
  # Returns the parsed response from gpgverify.
  def request(type, body: nil, time: nil)
    unless route = ROUTES[type]
      raise Error, "request type not implemented: #{type}"
    end

    response = record_stats(route) do
      record_trace(route) do
        http_request(route, body, time)
      end
    end

    case response.headers[CONTENT_TYPE_HEADER]
    when Mime[:msgpack]
      MessagePack.unpack(response.body)
    when Mime[:pgp_keys], Mime[:pgp_signature]
      response.body
    else
      raise BadResponse
    end
  rescue Faraday::Error => e
    Failbot.report(e, app: GitSigning::FAILBOT_APP)
    raise Unavailable
  end

  # Make the actual HTTP request to a gpgverify instance.
  #
  # route - A Hash description of the route from the ROUTES constant.
  # body  - The body to encode in the HTTP request or nil.
  #
  # Returns a Faraday::Response.
  def http_request(route, body, time)
    response = connection.send(route[:method]) do |req|
      req.options.timeout = REQUEST_TIMEOUT
      req.url route[:path]
      req.headers[ACCEPT_HEADER] = route[:accept] if route.key?(:accept)
      req.headers[CONTENT_TYPE_HEADER] = route[:content_type] if route.key?(:content_type)
      req.headers[TIME_HEADER] = time.rfc3339 if route.key?(:time_header) && time.present?

      if route[:method] == :post
        req.body = case route[:content_type]
        when Mime[:msgpack]
          MessagePack.pack(body)
        else
          body
        end
      end
    end

    case response.status
    when 502
      # haproxy returns 502 if the backend is down
      raise Unavailable
    when 404
      # Nginx returns 404 if gpgverify is down
      raise Unavailable
    when 400..Float::INFINITY
      # application-level error from gpgverify
      raise ServerError.from_response(response)
    end

    response
  end

  # Trace a request to gpgverify.
  #
  # route - A Hash description of the route from the ROUTES constant.
  # &blk  - The block to call to make the HTTP request.
  #
  # Returns the result from calling blk.
  def record_trace(route, &blk)
    tags = {
      "peer.service" => "gpgverify",
      "http.method"  => route[:method].to_s,
      "http.url"     => route[:path],
    }

    GitHub.tracer.in_span(route[:type], kind: :internal, attributes: tags) do |span|
      return blk.call.tap do |response|
        span.set_attribute("http.status_code", response.status)
      end
    end
  end

  # Send stats about a gpgverify call to datadog.
  #
  # route - A Hash description of the route from the ROUTES constant.
  # &blk  - The block to call to make the HTTP request.
  #
  # Returns the result from calling blk.
  def record_stats(route, &blk)
    start = Time.now
    tags = [
      "rpc_operation:#{route[:type]}",
      "route:#{route[:path]}",
    ]

    blk.call.tap do |response|
      tags << "status:#{response.status}"
    end
  rescue => e # rubocop:todo Lint/GenericRescue
    tags << "err:#{e.class.name}"
    raise
  ensure
    ms = (Time.now - start) * 1000
    GitHub.dogstats.timing("rpc.gpgverify.time", ms, tags: tags)
  end

  # Cache multiple values.
  #
  # key_prefix - A Symbol or String to prefix cache-keys with for this type of
  #              operation.
  # inputs     - Array of parameters to use as cache-key parts and to pass to
  #              the provided block for cache misses.
  # &block     - Block to call to get value to cache. The block will be called
  #              with the provided inputs that were cache misses. Should return
  #              values to cache in the same order as inputs.
  #
  # Returns Array of cache results mixed with values from calling the block.
  # The order of the results matches the order of `inputs` argument.
  def cache_multi(key_prefix, inputs, &block)
    keys = inputs.map { |i| cache_key(key_prefix, i) }
    results = GitHub.cache.get_multi(keys)

    input_to_key = inputs.zip(keys).to_h

    misses = input_to_key.select do |_input, key|
      results[key].nil?
    end.keys

    new_results = misses.any? ? block.call(misses) : []

    misses.zip(new_results).each do |input, result|
      key = input_to_key[input]
      GitHub.cache.set(key, result, CACHE_TTL)
      results[key] = result
    end

    # Preserve ordering from params
    inputs.map do |input|
      results[input_to_key[input]]
    end
  end

  # Generate a cache key.
  #
  # parts - An Array of values to construct key from.
  #
  # Returns a String.
  def cache_key(*parts)
    serialized = MessagePack.pack(parts)
    hash = CACHE_DIGEST.hexdigest(serialized)
    [CACHE_BASE_KEY, CACHE_VERSION, hash].join(":")
  end

  def service_circuit_breaker(&blk)
    with_cb(Resilient::CircuitBreaker.get("gpgverify", instrumenter: GitHub), &blk)
  end

  def signing_circuit_breaker(&blk)
    with_cb(Resilient::CircuitBreaker.get("gpgverify-signing", instrumenter: GitHub), &blk)
  end

  def with_cb(cb, &blk)
    raise Unavailable unless cb.allow_request?

    begin
      blk.call.tap { cb.success }
    rescue GpgVerify::Error
      cb.failure
      raise
    end
  end
end

require "gpg_verify/errors"
