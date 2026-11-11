# typed: true
# frozen_string_literal: true

module Api::App::CachingHelpers

  # Set the appropriate caching headers for the response.
  #
  # options - The Hash of per-action overriddable options.
  #           :last_modified - The Time that the resource represented by the
  #                            response was last updated (optional).
  #           :etag          - The String value to use as the ETag header
  #                            (optional).
  #           :body          - The String response body to use as the basis for
  #                            generating an ETag (optional).
  #           :max_age       - The FixNum Cache-Control max-age in seconds.
  #                            (default: 60).
  #
  # If the response already has an ETag or Last-Modified header set, or if the
  # response has a Cache-Control header set to "no-cache", this method will
  # *not* set any caching headers on the response.
  #
  # If the options Hash includes :last_modified, this method will set the
  # Last-Modified response header using the given value.
  #
  # If the options Hash includes :etag, this method will set the ETag response
  # header to the given value. Otherwise, if the options Hash includes :body,
  # and the response has an appropriate status code for an ETag, then this
  # method will generate an ETag based on the given body.
  #
  # Returns nothing.
  def set_caching_headers!(options = {})
    CacheHeaderSetter.new(self, options).apply
  end

  # Calling `cache_control "no-cache"` will cause `set_caching_headers!` above to no-op,
  # because this code determines that the controller has (or, should have) already set
  # etag and vary headers as appropropriate.
  #
  # However, as shown in https://github.com/github/github/issues/152909,
  # that's not the case in practice.
  #
  # This method is for setting Vary when `cache_control "no-cache"` was used.
  # It's hooked up through this file so that we'll use the same logic for
  # determining which headers to name in the Vary value.
  def set_vary_header
    CacheHeaderSetter.new(self).set_vary_header
  end

  class CacheHeaderSetter

    attr_reader :sinatra_app, :options

    DEFAULTS = {
      max_age: 60,
      vary_headers: %w[Accept],
    }

    AUTHENTICATED_VARY_HEADERS = %w[Authorization Cookie X-GitHub-OTP]

    def initialize(sinatra_app, options = {})
      @sinatra_app = sinatra_app
      @options = options
    end

    def apply
      return if skip_caching? || noncacheable?

      cache_control_value = sinatra_app.cache_control(*cache_control_headers)
      etag_value = etag

      sinatra_app.headers["Cache-Control"] = cache_control_value if cache_control_value

      # Both `last_modified` and `etag` `halt` with a 304 via Sinatra. According to the spec,
      # 200 and 304 requests must return the same headers. To implement this, we'll set
      # the required headers before relying on Sinatra to handle the rest.
      set_vary_header
      sinatra_app.headers["ETag"] = etag_value.inspect

      sinatra_app.headers["Last-Modified"] = last_modified.httpdate if last_modified

      # Convert weak etags to strong etags for less strict matching
      if sinatra_app.env["HTTP_IF_NONE_MATCH"] && sinatra_app.env["HTTP_IF_NONE_MATCH"].start_with?("W/")
        sinatra_app.env["HTTP_IF_NONE_MATCH"] = sinatra_app.env["HTTP_IF_NONE_MATCH"][2..-1]
      end
      sinatra_app.etag(etag_value)

      return unless last_modified

      sinatra_app.last_modified(last_modified)
    end

    def set_vary_header
      sinatra_app.headers["Vary"] = vary_headers.join(", ")
    end

    # Internal: Determine whether any caching headers should be applied to the
    # response.
    #
    # Returns a Boolean.
    def skip_caching?
      headers = sinatra_app.headers

      options[:skip_caching_headers] || (headers["Cache-Control"] && headers["Cache-Control"].include?("no-cache")) ||
        headers.key?("ETag") || headers.key?("Last-Modified")
    end

    def noncacheable?
      !cacheable?
    end

    # Internal: Determines whether we have enough information to apply caching
    # headers to the response.
    #
    # Returns a Boolean.
    def cacheable?
      options[:last_modified] || options[:etag] || etag_derivable_from_body?
    end

    def etag_derivable_from_body?
      etag_status? && etag_body?
    end

    def etag_status?
      sinatra_app.status == 200 || sinatra_app.status == 201
    end

    def etag_body?
      !!body
    end

    def vary_headers
      return @vary_headers if @vary_headers

      @vary_headers = DEFAULTS[:vary_headers]
      @vary_headers += AUTHENTICATED_VARY_HEADERS if authenticated_request?

      @vary_headers
    end

    def last_modified
      options[:last_modified]
    end

    def etag
      options[:etag] || etag_with(body)
    end

    # Internal: Construct an ETag using the Vary headers and the given
    # fingerprint.
    #
    # fingerprint - The String that uniquely identifies the response body.
    #
    # Returns the ETag String, or nil if the given fingerprint is nil.
    def etag_with(fingerprint)
      return if fingerprint.nil?

      etag_string = (variable_request_header_values << fingerprint.b).join(":")
      ::Digest::SHA256.hexdigest etag_string
    end

    # Returns a string with binary encoding since users can send garbage bites in header values.
    # We just use these to create a digest and the digest doesn't care if the encoding is encoding is UTF-8.
    def variable_request_header_values
      header_values = []
      vary_headers.sort.each do |key|
        key = "HTTP_#{key.upcase.gsub("-", "_")}"
        # The headers are parsed as ASCII-8BIT, but a user could have sent
        # garbage characters which will :boom: when `.join`ed with a fingerprint
        # _if_ the fingerprint contains UTF-8 characters.
        # See https://github.com/github/github/issues/131858
        header_value = sinatra_app.env[key]
        # If the header isn't present, the value will be `nil`; skip nils.
        if header_value
          header_values << fix_header_value_encoding(header_value)
        end
      end
      header_values
    end

    # `header_value` was pulled out of `sinatra_app.env`, so
    # it might be a string or an array of strings.
    #
    # This method returns the same kind of data, but with strings forced to UTF-8.
    def fix_header_value_encoding(header_value)
      case header_value
      when String
        header_value.b
      when Array
        header_value.map { |v| fix_header_value_encoding(v) }
      else
        # This is some non-string, non-array value in the Rack env.
        # Don't log the value incase it somehow has PII
        raise ArgumentError, "Unexpected header value (#{header_value.class})"
      end
    end

    def cache_control_headers
      max_age = options[:max_age] || DEFAULTS[:max_age]

      [
        authenticated_request? ? "private" : "public",
        { "max-age" => max_age, "s-maxage" => max_age },
      ]
    end

    def authenticated_request?
      sinatra_app.current_user
    end

    def body
      options[:body]
    end
  end
end
