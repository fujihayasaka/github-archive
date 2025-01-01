# typed: true
# frozen_string_literal: true

module GitHub
  module JSON
    module CachedFetchRemoteUrl
      module_function

      CACHE_TTL            = 5.minutes.to_i
      OPEN_TIMEOUT_SECONDS = 0.5
      TIMEOUT_SECONDS      = 1

      class FetchError < StandardError; end

      # Queries a provided remote URL with `Faraday` and caches the result to
      # be refetched periodically.
      #
      # url:           The URL to fetch with `Faraday`.
      # default_value: The value to return if a valid new value was not
      #                successfully fetched.
      # cache_key:     The `GitHub.cache` key to use for storing the fetched,
      #                parsed result.
      # hash_subkey:   The key in the fetched, parsed Hash result to return the
      #                value from. Defaults to `nil` in which case the fetched,
      #                parsed result is returned as-is.
      #
      # Returns the JSON hash subkey values, JSON hash, cached value or the
      # passed `default_value`.
      def fetch(url:, default_value:, cache_key:, hash_subkey: nil)
        default_value.freeze
        return default_value unless faraday

        GitHub.cache.fetch(cache_key, ttl: CACHE_TTL) do
          json = begin
            response = faraday.get(url)
            ::JSON.parse response.body
          rescue Faraday::Error, ::JSON::ParserError => e
            GitHub.logger.error(e)

            # raise generic FetchError for Sentry
            # more details can be found in Splunk
            error = FetchError.new("Problem fetching from cache or parsing JSON.")
            Failbot.report_user_error(error)
            nil
          end

          if json.nil?
            next default_value
          elsif json.blank?
            Failbot.report(RuntimeError.new("CachedFetchRemoteUrl: blank JSON at #{url}!"))
            next default_value
          end

          next json if hash_subkey.blank?

          hash_subkey_values = json[hash_subkey.to_s]
          if hash_subkey_values.blank?
            Failbot.report(RuntimeError.new("CachedFetchRemoteUrl: blank JSON #{hash_subkey} at #{url}!"))
            next default_value
          end

          hash_subkey_values
        end
      end

      def faraday
        return if Rails.env.test?
        @faraday ||= Faraday.new do |f|
          f.options[:open_timeout] = OPEN_TIMEOUT_SECONDS
          f.options[:timeout] = TIMEOUT_SECONDS
          f.adapter(Faraday.default_adapter)
        end
      end
    end
  end
end
