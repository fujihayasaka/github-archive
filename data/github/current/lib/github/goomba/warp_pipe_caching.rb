# typed: true
# frozen_string_literal: true

require "scientist"

module GitHub::Goomba
  module WarpPipeCaching
    include Scientist
    DEFAULT_RESULT_CACHE_KEYS = [:output, :html_safe].freeze
    DEFAULT_CACHE_PARTITION = :htmlpipeline.freeze

    # Public: Returns the cache key for the pipeline based on the context and the content.
    # Combination of all the filters enabled for the run based on the context, each filters cach_key
    # based on the context, the cache digest of the filters, and the content.
    # context: Markdown pipeline context at time of render
    # content: Markdown content to be rendered
    # cache_postfix: String to append to the cache key
    # cache_results: Array of keys to cache from the returned result used to calculate keys
    #                so different caches can store different information.
    def cache_key(context, content, cache_prefix = "", cache_results: DEFAULT_RESULT_CACHE_KEYS)
      context = context.merge(stage: :cache_key_generation)
      content = context.has_key?(:blob) ? context[:blob].data : (content || "")
      enabled_filters, filter_keys = enabled_filters_keys(context)
      enabled_sanitizer = enabled_sanitizer(context)
      [
        cache_prefix,
        "warp_pipe_cache",
        sha(enabled_filters),
        sha(content),
        sha(filter_keys),
        sha(cache_results.join(":")),
        blob_cache_keys(context[:blob]),
        GitHub::Goomba::Reference::CACHE_KEY,
        "goomba:#{Goomba::CACHE_VERSION}",
        sha(enabled_sanitizer)
      ].join(":")
    end

    def build_cache(cache_settings, context, input)
      cache_settings = @default_cache_settings.merge(cache_settings)
      Cache.new(cache_settings, @stats_key, context, input, self)
    end

    private

    def sha(str)
      Digest::SHA256.hexdigest(str)
    end

    def enabled_sanitizer(context)
      sanitizer = context.fetch(:sanitizer, @sanitizer)
      return "" if sanitizer.nil?

      sanitizer.to_h.to_s
    end

    # Private: Returns a hash of all the enabled filters names as well as a string of
    # the cache keys for each filter.
    def enabled_filters_keys(context)
      filters = @input_filters + @node_filters + @output_filters
      filter_keys = []
      running_filters = filters.select { |filter| filter.enabled?(context) }.map do |filter|
        unless filter.is_a?(Class)
          filter = filter.class
        end
        add_filter_cache_key(filter, filter_keys, context)
        @cache_digest[filter]
      end.sort.join("")
      [running_filters, filter_keys.join("_")]
    end

    def add_filter_cache_key(filter, filter_keys, context)
      if filter.respond_to?(:cache_key)
        filter_key = filter.cache_key(context)
        filter_keys << filter_key if filter_key
      end
    end

    def blob_cache_keys(blob)
      return "" unless blob
      [
        # We of course want to re-render if the blob's contents change.
        blob.oid,
        # The blob's filename affects what markup language it's interpreted as.
        # Ideally we'd get GitHub::Markup to tell us what language the file is,
        # but there's no API for that currently.
        blob.name.b,
        # Is the blob for a snippet for Gist? If so, include a snippet key in the cache
        # This ensures the full version, and the snippet get cached independently.
        ("snippet" if blob.snippet?),
      ].reject(&:blank?).join(":")
    end

    # Private: Creates a hash digest of the filters used in this pipeline, created
    # at initialization of each pipeline which happens when the application is deployed
    # or started.
    def create_filter_digest(filters)
      filters.inject({}) do |digests, filter|
        unless filter.is_a?(Class)
          filter = filter.class
        end
        file = Object.const_source_location(filter.to_s)
        if file && file[0]
          digest = Digest::SHA256.file(file[0]).hexdigest
        else # fallback to class name if we can't find the file, I have only seen this happen in a test.
          digest = filter.name
        end
        digests[filter] = digest
        digests
      end
    end

    class Cache
      include Scientist
      attr_reader :use_cache, :cache_key, :skip_cached_results

      def initialize(cache_settings, stats_key, context, input, pipeline)
        @use_cache = cache_settings.fetch(:use_cache, false)
        @skip_cached_results = cache_settings.fetch(:skip_cached_results, false)
        @ttl = cache_settings.fetch(:ttl, 0)
        @cached_result_keys = cache_settings.fetch(:cache_result_keys, DEFAULT_RESULT_CACHE_KEYS)
        @cache_key_prefix = cache_settings.fetch(:cache_prefix, "")
        @cache_partition = cache_settings.fetch(:cache_partition, DEFAULT_CACHE_PARTITION)
        @stats_key = stats_key
        @cache_key = pipeline.cache_key(context, input, @cache_key_prefix, cache_results: @cached_result_keys) if use_cache
      end

      def fetch_cached_result
        return nil unless use_cache
        return nil if skip_cached_results
        cached = cache_partition.get(cache_key)
        if cached.nil?
          GitHub.dogstats.increment("html_pipeline.cache.miss", tags: ["stats_key:#{@stats_key}", "cache_partition:#{@cache_partition}"])
        else
          GitHub.dogstats.increment("html_pipeline.cache.hit", tags: ["stats_key:#{@stats_key}", "cache_partition:#{@cache_partition}"])
        end
        cached
      end

      def set_cached_result(result)
        return nil unless use_cache
        cached_results_to_store = result.to_h.slice(*@cached_result_keys)
        cache_partition.set(cache_key, cached_results_to_store, @ttl, false)
      end

      def cache_partition
        GitHub.cache.for_partition(@cache_partition)
      end
    end
  end
end
