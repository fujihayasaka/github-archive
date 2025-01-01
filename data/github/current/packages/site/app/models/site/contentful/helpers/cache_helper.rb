# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Helpers
      module CacheHelper
        extend T::Sig
        extend T::Helpers
        include GitHub::Memoizer
        include Kernel

        abstract!

        sig { abstract.returns(String) }
        def cache_key; end

        sig { params(data: T.nilable(T::Hash[T.untyped, T.untyped])).void }
        def save_page_data_in_cache(data)
          # We don't save blank data in the cache if the key does not exist. This is to avoid
          # polluting the cache with useless data.
          return if data.blank? && !GitHub.kv.exists(cache_key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv

          json_data_uncompressed = JSON.generate(data)

          GitHub.dogstats.gauge("site.contentful.pages.json_byte_size.uncompressed", json_data_uncompressed.bytesize, tags: ["cache_key:#{cache_key}"])

          json_data_compressed = Zlib::Deflate.deflate(json_data_uncompressed)
          GitHub.dogstats.gauge("site.contentful.pages.json_byte_size.compressed", json_data_compressed.bytesize, tags: ["cache_key:#{cache_key}"])

          ActiveRecord::Base.connected_to(role: :writing) do
            # We make it expire in 1 week to prevent stale data polluting the cache.
            GitHub.kv.set(cache_key, json_data_compressed, expires: 1.week.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        rescue GitHub::KV::ValueLengthError
          GitHub.dogstats.increment("site.contentful.pages.exceeded_cache_max_size", tags: ["cache_key:#{cache_key}"])
          GitHub.logger.warn("Exceeded cache max size",
            "gh.contentful.cache_key": cache_key,
            "code.namespace": self.class.name,
            "code.function": __method__
          )

          # Once data for a given cache key exceeds the cache max size,
          # we remove it from the cache to ensure we fetch data from Contentful instead of
          # showing stale data.
          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.kv.del(cache_key) # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        rescue GitHub::KV::UnavailableError
          # GitHub::KV is unavailable, but we can continue. Caching is an optional feature
          # and we can fetch the data from Contentful if the cache store is down. We just send
          # some information to Datadog/Splunk to keep track of how often this happens.
          GitHub.dogstats.increment("site.contentful.pages.cache_unavailable")
          GitHub.logger.warn("GitHub::KV is unavailable",
            "gh.contentful.cache_key": cache_key,
            "code.namespace": self.class.name,
            "code.function": __method__
          )
        rescue GitHub::KV::KeyLengthError
          report_long_cache_key_error
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        memoize def page_cached_data
          json_data_compressed = GitHub.kv.get(cache_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv

          if json_data_compressed.blank?
            GitHub.dogstats.increment("site.contentful.pages.cache_miss", tags: ["cache_key:#{cache_key}"])

            return nil
          end

          GitHub.dogstats.increment("site.contentful.pages.cache_hit", tags: ["cache_key:#{cache_key}"])

          json_data_uncompressed = Zlib::Inflate.inflate(json_data_compressed)
          JSON.parse(json_data_uncompressed, object_class: HashWithIndifferentAccess)
        rescue Zlib::DataError => error
          GitHub.logger.error("Failed to uncompress #{cache_key}.", "Error": error.inspect)

          nil
        rescue GitHub::KV::KeyLengthError
          report_long_cache_key_error

          nil
        end

        private

        sig { void }
        def report_long_cache_key_error
          GitHub.dogstats.increment("site.contentful.pages.cache_key_too_long")

          GitHub.logger.warn("Exceeded cache key max length",
            "gh.contentful.cache_key": cache_key,
            "code.namespace": self.class.name,
            "code.function": __method__
          )
        end
      end
    end
  end
end
