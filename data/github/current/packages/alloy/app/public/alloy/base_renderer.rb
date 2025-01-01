# typed: strict
# frozen_string_literal: true

module Alloy
  class BaseRenderer
    ASSETS_PATH = T.let("public/assets", String)
    HMAC_TOKEN_DIGEST = OpenSSL::Digest::SHA256
    MAX_SIZE = T.let(1.megabyte, Integer)

    sig { params(request: T::Hash[T.untyped, T.untyped], metadata: T::Hash[T.untyped, T.untyped]).void }
    def initialize(request:, metadata: {})
      @request = request
      @metadata = metadata
      @app_name = T.let(request[:name], String)
      @tier = T.let(request[:tier], Integer)

      payload = {
        arg: @request,
        metadata: @metadata,
        manifestUrl: Alloy::Manifest.full_manifest_url
      }
      payload[:cdnPath] = "http://github.localhost/webpack/" if GitHub.webpack_dev_server_enabled?
      @request_payload = T.let(payload.to_json, String)
    end

    # Returns the HTML rendered by Alloy.
    #
    # @param request [T::Hash[T.untyped, T.untyped]] the request payload to pass to the Alloy handler
    # @returns [Alloy::Response, ConcurrentFaraday::FutureResponse] the response from Alloy
    sig { returns(T.any(Alloy::Response, ConcurrentFaraday::FutureResponse[T.untyped])) }
    def render
      raise NotImplementedError, "Implement in a subclass"
    end

    sig { returns(T::Hash[String, String]) }
    def request_headers
      {
        "REQUEST_HMAC" => hmac_token,
        "Content-Type" => "application/json",
        Alloy::Constants::REACT_APP_HEADER => @app_name,
      }
    end

    sig { returns(String) }
    def hmac_token
      timestamp = Time.now.to_i.to_s
      digest = HMAC_TOKEN_DIGEST.new
      hmac = OpenSSL::HMAC.new(GitHub.alloy_api_hmac_key, digest)
      hmac << timestamp
      hmac << Alloy::Manifest.full_manifest_url
      "#{timestamp}.#{hmac}"
    end

    sig { returns(T::Boolean) }
    def payload_too_large?
      @request_payload.bytesize > MAX_SIZE
    end

    sig { params(block: T.proc.returns(Faraday::Response)).returns(Faraday::Response) }
    def with_request_timing(&block)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      response = yield

      timing = (1000 * (Process.clock_gettime(Process::CLOCK_MONOTONIC) - now)).round(2)
      report_request_timing(timing:, response:)

      response
    end

    sig { params(timing: T.any(Integer, Float), response: Faraday::Response).void }
    def report_request_timing(timing:, response:)
      tags = ["app_name:#{@app_name}", "status_code:#{response.status}", "status:#{response.success? ? "success" : "failure"}"]
      tags << "controller:#{@metadata[:controller]}" if @metadata[:controller]
      tags << "action:#{@metadata[:action]}" if @metadata[:action]
      tags << "referrer_controller:#{@metadata[:referrer_controller]}" if @metadata[:referrer_controller]
      tags << "referrer_action:#{@metadata[:referrer_action]}" if @metadata[:referrer_action]
      tags << "logged_in:#{@metadata[:logged_in].present?}"
      tags << "staff:#{@metadata[:staff]}"
      tags << "catalog_service:#{@metadata[:catalog_service]}"
      tags << "tier:#{@tier}"

      GitHub.dogstats.distribution("alloy.gh.render.time", timing, tags: tags)
    end

    sig { returns(Faraday::Connection) }
    def self.faraday_connection
      raise NotImplementedError, "Implement in a subclass"
    end

    sig { params(conn: T.untyped).void }
    def self.setup_connection(conn)
      raise NotImplementedError, "Implement in a subclass"
    end

    sig { returns(T.nilable(String)) }
    def self.request_url
      GitHub.context[:ui_sha_override] ? GitHub.alloy_staging_url : GitHub.alloy_url
    end
  end
end
