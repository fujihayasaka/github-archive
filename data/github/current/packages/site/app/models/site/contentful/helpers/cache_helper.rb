# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Helpers
      module CacheHelper
        extend T::Helpers
        include GitHub::Memoizer
        include Kernel
        include ObservabilityHelper

        abstract!

        JsonLikeType = T.type_alias { T::Hash[T.untyped, T.untyped] }

        sig { abstract.returns(Page::CacheKey) }
        def cache_key; end

        sig { returns(T::Boolean) }
        def cached?
          Site::KV.store.exists(cache_key.to_s).value { false }
        end

        sig { overridable.params(data: JsonLikeType).void }
        def save_page_data_in_cache(data)
          json_data_uncompressed = JSON.generate(data)

          GitHub.dogstats.distribution("site.contentful.pages.json_byte_size.dist.uncompressed", json_data_uncompressed.bytesize, tags: metric_tags)
          GitHub.logger.info(
            "Compressing page",
            "gh.contentful.uncompressed_page_size": json_data_uncompressed.bytesize,
            **log_context,
          )

          json_data_compressed = Zlib::Deflate.deflate(json_data_uncompressed)
          GitHub.dogstats.distribution("site.contentful.pages.json_byte_size.dist.compressed", json_data_compressed.bytesize, tags: metric_tags)
          GitHub.logger.info(
            "Page compressed",
            "gh.contentful.compressed_page_size": json_data_compressed.bytesize,
            **log_context,
          )

          ActiveRecord::Base.connected_to(role: :writing) do
            # We make it expire in 1 week to prevent stale data polluting the cache.
            Site::KV.store.set(cache_key.to_s, json_data_compressed, expires: 1.week.from_now)
          end
        rescue GitHub::KV::ValueLengthError
          GitHub.dogstats.increment("site.contentful.pages.exceeded_cache_max_size", tags: metric_tags)
          GitHub.logger.warn("Exceeded cache max size",
            **log_context,
          )

          # Once data for a given cache key exceeds the cache max size,
          # we remove it from the cache to ensure we fetch data from Contentful instead of
          # showing stale data.
          ActiveRecord::Base.connected_to(role: :writing) do
            Site::KV.store.del(cache_key.to_s)
          end
        rescue GitHub::KV::UnavailableError
          # GitHub::KV is unavailable, but we can continue. Caching is an optional feature
          # and we can fetch the data from Contentful if the cache store is down. We just send
          # some information to Datadog/Splunk to keep track of how often this happens.
          GitHub.dogstats.increment("site.contentful.pages.cache_unavailable", tags: metric_tags)
          GitHub.logger.warn("GitHub::KV is unavailable",
            **log_context,
          )
        rescue GitHub::KV::KeyLengthError
          report_long_cache_key_error
        end

        sig { returns(T.nilable(JsonLikeType)) }
        memoize def page_cached_data
          json_data_compressed = Site::KV.store.get(cache_key.to_s).value { nil }

          if json_data_compressed.blank?
            GitHub.dogstats.increment("site.contentful.pages.cache_miss", tags: metric_tags)
            GitHub.logger.info(
              "Contentful cache miss",
              **log_context,
            )

            return nil
          end

          GitHub.dogstats.increment("site.contentful.pages.cache_hit", tags: metric_tags)
          GitHub.logger.info(
            "Contentful cache hit",
            **log_context,
          )

          json_data_uncompressed = Zlib::Inflate.inflate(json_data_compressed)
          JSON.parse(json_data_uncompressed, object_class: HashWithIndifferentAccess)
        rescue Zlib::DataError => error
          GitHub.dogstats.increment("site.contentful.pages.decompression_failed", tags: metric_tags)
          GitHub.logger.error("Failed to decompress page.", **log_context, exception: error)

          nil
        rescue GitHub::KV::KeyLengthError
          report_long_cache_key_error

          nil
        end

        private

        sig { void }
        def report_long_cache_key_error
          GitHub.dogstats.increment("site.contentful.pages.cache_key_too_long", tags: metric_tags)

          GitHub.logger.warn("Exceeded cache key max length",
            **log_context,
          )
        end
      end
    end
  end
end
