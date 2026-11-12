# frozen_string_literal: true

require "faraday"

# Faraday middleware to cache responses based on etags
module Faraday
  class EtagCache < Faraday::Middleware
    attr_reader :cache

    def initialize(app, options = {})
      super(app)
      @cache = options.fetch(:cache) { raise ArgumentError, ":cache is required" }
    end

    def call(request_env)
      return @app.call(request_env) unless request_env[:method].in?(%i(get head))

      cached_response = @cache.read(cache_key(request_env))

      set_etag_header(request_env, cached_response) if cached_response

      @app.call(request_env).on_complete do |response_env|
        cache_response(response_env, cached_response)
      end
    rescue TypeError
      retrying ||= false
      raise if retrying

      retrying = true
      @cache.delete(cache_key(request_env))
      retry
    end

    private

    def set_etag_header(env, cached_response)
      env[:request_headers]["If-None-Match"] =
        cached_response[:response_headers]["Etag"]
    end

    def cache_response(env, cached_response)
      if env[:status] == 304
        env.update(cached_response)
      elsif env[:status] == 200 && env[:response_headers]["Etag"]
        @cache.write(cache_key(env), env, expires_in: 1.hour)
      end
    end

    def cache_key(env)
      if env[:request_headers]["Authorization"]
        auth_digest = OpenSSL::Digest::SHA256.hexdigest(
          env[:request_headers]["Authorization"],
        )
        "faraday_etags/#{env[:url]}+#{auth_digest}"
      else
        "faraday_etags/#{env[:url]}"
      end
    end
  end
end
