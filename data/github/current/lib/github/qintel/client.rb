# typed: true
# frozen_string_literal: true

module GitHub
  module Qintel
    class Client
      URL                   = "https://qwatch-files.qintel.com"
      CONNECT_TIMEOUT       = 5.seconds
      REQUEST_TIMEOUT       = 5.minutes
      HMAC_DIGEST_ALGORITHM = "SHA256"

      attr_reader :secret, :key, :url, :request_options

      def initialize(secret:, key:, proxy: nil, url: URL, timeout: REQUEST_TIMEOUT)
        @secret = secret
        @key = key
        @url = url
        @request_options = {
          connecttimeout: CONNECT_TIMEOUT,
          timeout: timeout,
        }

        unless proxy.nil?
          @request_options[:proxy] = proxy
        end
      end

      # Make a GET request to the given path.
      #
      # WARNING: This doesn't conform to the Qintel docs and was reverse
      # engineered from thier Python SDK.
      #
      # path - The String path to request.
      # &blk - Optional block to call with response data as it's received.
      #
      # Returns the String body of the response or raises a subclass of
      # Qintel::Error.
      def get(path = nil, &blk)
        time = Time.now
        signature = signature(path, time)
        full_url = url_for_path(path)

        request = Typhoeus::Request.new(full_url, request_options.merge(headers: {
          "Timestamp"      => time.to_i.to_s,
          "Authentication" => "#{key}:#{signature}",
        }))

        request.on_complete do |response|
          case response.return_code
          when :ok
            # 🎉
          when :couldnt_connect
            raise ConnectError
          when :operation_timedout
            raise TimeoutError
          when :write_error
            # our on_body block failed. We'll be raising again shortly...
          else
            raise RequestFailed, response.return_code
          end
        end

        request.on_headers do |response|
          case response.code
          when 200
            # 🎉
          when 400...500
            raise ClientError, response.code
          when 500...600
            raise ServerError, response.code
          else
            raise BadResponseError, response.code
          end
        end

        if blk.nil?
          response = request.run
          return response.body
        end

        # When providing an `on_body` callback, we're supposed to return :abort
        # when we want to give up on a request rather than raising. Apparently
        # raising can result in a memory leak in libcurl. So, we backup any
        # error here and re-raise it once we're finished running the request.
        blk_error = T.cast(nil, T.nilable(StandardError))

        request.on_body do |chunk|
          begin
            blk.call(chunk)
            nil
          rescue => e # rubocop:todo Lint/GenericRescue
            blk_error = e
            :abort
          end
        end

        request.run
        raise blk_error unless blk_error.nil?

        nil
      end

      # Build out a full URL for the given path.
      #
      # path - The String path.
      #
      # Returns a String URL.
      def url_for_path(path)
        @parsed_url ||= Addressable::URI.parse(url)
        @parsed_url.merge(path: path).to_s
      end

      # Calculate a request signature for a request.
      #
      # path - The String path we'll be requesting.
      # time - The Time we're making the request.
      #
      # Returns a URL encoded, base64 encoded String signature.
      def signature(path, time)
        raise Error, "no qintel secret" if secret.blank?

        binary_signature = OpenSSL::HMAC.digest(
          HMAC_DIGEST_ALGORITHM,
          secret,
          signature_payload(path, time),
        )

        modified_url_encode(Base64.strict_encode64(binary_signature))
      end

      # The value we sign to authenticate our requests.
      #
      # WARNING: This doesn't conform to the Qintel docs and was reverse
      # engineered from thier Python SDK.
      #
      # path - The String path we'll be requesting.
      # time - The Time we're making the request.
      #
      # Returns a String.
      def signature_payload(path, time)
        "get\n#{time.to_i}\n#{path}\n"
      end

      # Perform a subset of URL encoding.
      #
      # WARNING: This doesn't conform to the Qintel docs and was reverse
      # engineered from thier Python SDK. The API returns 401 if `/` is encoded.
      #
      # raw - The unencoded String to modify.
      #
      # Returns a String.
      def modified_url_encode(raw)
        raw.gsub("+", "%2B").gsub("=", "%3D")
      end
    end
  end
end
