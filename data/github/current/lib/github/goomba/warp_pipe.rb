# typed: true
# frozen_string_literal: true
require_relative "warp_pipe_caching"

module GitHub::Goomba
  # Construct a WarpPipe for running multiple filters.  A pipeline is created once
  # with one to many filters, and it then can be `call`ed many times over the course
  # of its lifetime with input.
  #
  # input_filters   - Array of InputFilter classes. Each must respond to
  #                   new(context, result) and return an instance that responds
  #                   to call(input) and returns a modified String. Filters
  #                   are performed in the order provided.
  # sanitizer       - An optional Goomba::Sanitizer.
  # node_filters    - Array of NodeFilter classes. Each must respond to
  #                   new(context, result) and return an instance that responds
  #                   to #call(node) and, optionally, #selector. Filters that
  #                   operate on the same node are performed in the order
  #                   provided.
  # output_filters  - Array of OutputFilter classes. Each must respond to
  #                   new(context, result) and return an instance. Filters are
  #                   performed in the order provided.
  # default_context - The default context hash. Values specified here will be merged
  #                   into values from the each individual pipeline run.  Can NOT be
  #                   nil.  Default: empty Hash.
  # result_class    - The default Class of the result object for individual
  #                   calls.  Default: Hash.  Protip:  Pass in a Struct to get
  #                   some semblance of type safety.
  # stats_key       - An optional String Graphite key for metrics collection.
  #                   If specified, stats are recorded both under
  #                   github.goomba.warp_pipe and
  #                   github.goomba.warp_pipes.<stats_key>.
  # default_cache_settings - The default cache settings for the pipeline. Values here
  #                          will be merged into the cache settings for each
  #                          individual pipeline run. Default: empty Hash.
  class WarpPipe
    include GitHub::Goomba::WarpPipeCaching

    REFERENCE_FILTERS = [
      GitHub::Goomba::Reference::UserFilter,
      GitHub::Goomba::Reference::CurrentViewerFilter,
      GitHub::Goomba::Reference::RepositoryResourceFilter,
      GitHub::Goomba::Reference::RepositoryFilter,
      GitHub::Goomba::Reference::OrganizationResourceFilter,
      GitHub::Goomba::Reference::SecuredAssetFilter,
      GitHub::Goomba::Reference::MemexSecuredAssetFilter,
      GitHub::Goomba::Reference::GistSecuredAssetFilter,
      GitHub::Goomba::Reference::SavedReplySecuredAssetFilter,
      GitHub::Goomba::Reference::GHESSecuredLegacyAssetFilter,
    ].freeze

    attr_writer :sanitizer
    attr_reader :stats_key, :cache_digest

    def initialize(input_filters: [], sanitizer: nil, node_filters: [], output_filters: [], post_cache_node_filters: [],
                   default_context: {}, result_class: Hash, stats_key: nil, default_cache_settings: {})
      @input_filters = input_filters
      @sanitizer = sanitizer
      @node_filters = node_filters
      @output_filters = output_filters
      @post_cache_node_filters = post_cache_node_filters
      @default_context = default_context
      @result_class = result_class
      @stats_key = stats_key
      @default_cache_settings = default_cache_settings
      @cache_digest = create_filter_digest(input_filters + node_filters + output_filters)
    end

    # Apply all filters in the pipe to the given input.
    #
    # Performs the following operations:
    #
    # 1. Passes the input through each InputFilter in order.
    # 2. Parses (and optionally sanitizes) the output of the last InputFilter
    #    into a Goomba::DocumentFragment.
    # 3. Serializes the DocumentFragment using the NodeFilters to filter text
    #    and element nodes.
    # 4. Passes the serialized HTML through each OutputFilter in order.
    #
    # input   - A String containing text or HTML.
    # context - The context hash passed to each filter. See the Filter docs
    #           for more info on possible values. This object MUST NOT be modified
    #           in place by filters.  Use the Result for passing state back.
    # result  - The result Hash passed to each filter for modification.  This
    #           is where Filters store extracted information from the content.
    # cache_settings - (Hash) A Hash of cache settings.
    #             :use_cache - (Boolean) Whether to use the cache.
    #             :cache_prefix - (String) The prefix to use for the cache key.
    #             :cache_result_keys - (Array) The keys to cache from the returned result. Anything
    #                             not in this list will not be cached. Anything in the list
    #                             must be serializable.
    #             :ttl - (Integer) The time to live for the cache.
    #             :cache_partition: (Symbol) The name of the cache partition to store the results in.
    #                               defaults to the htmlpipeline cache partition.
    #
    # Returns the result Hash after being filtered by this WarpPipe.  Contains an
    # :output key with the String HTML markup. If a sanitizer was used, also
    # contains a :html_safe key with the value true.
    def call(input, context = {}, result = nil, cache_settings: {})
      GitHub.instrument "goomba.warp_pipe.call", pipeline: self do
        async_call!(input, context, result, cache_settings: cache_settings).sync
      end
    end

    def async_call(input, context = {}, result = nil, cache_settings: {})
      GitHub.instrument "goomba.warp_pipe.async_call", pipeline: self do
        async_call!(input, context, result, cache_settings: cache_settings)
      end
    end

    # Like call but guarantee the value returned is a string of HTML markup.
    def to_html(input, context = {}, result = nil, cache_settings: {})
      async_to_html(input, context, result, cache_settings: cache_settings).sync
    end

    # Like async_call but guarantee the promise returned contains a string of HTML markup.
    def async_to_html(input, context = {}, result = nil, cache_settings: {})
      async_call(input, context, result, cache_settings: cache_settings).then do |result|
        GitHub::HTML::Result.to_html(result)
      end
    end

    # Returns a textual representation of the HTML returned by WarpPipe#call
    def to_text(input, context = {}, result = nil, cache_settings: {})
      async_to_text(input, context, result, cache_settings: cache_settings).sync
    end

    # Returns a textual representation of the HTML returned by WarpPipe#async_call
    def async_to_text(input, context = {}, result = nil, cache_settings: {})
      async_call(input, context, result, cache_settings: cache_settings).then do |result|
        GitHub::HTML::Result.to_text(result)
      end
    end

    # Public: Returns the key for the pipeline used as a tag in
    def dogstats_key
      @stats_key || "WarpPipe"
    end

    private

    def async_call!(input, context, result, cache_settings: {})
      preload_flags
      cache = build_cache(cache_settings, context, input)
      cached = cache.fetch_cached_result

      # We keep this around in case we need to re-run the pipeline due to a stale cache
      original_context = context

      scratch = {}

      context = @default_context.merge(context)
      context[:pipeline_run_id] ||= SecureRandom.hex
      context[:caching] = cache.use_cache
      context[:stage] = :input_transformation
      context = context.freeze

      result ||= @result_class.new
      unless cached.nil?
        # If there is cached content we don't need to run the whole pipeline, just the post-cache filters
        result.merge!(cached)
        return run_post_cache_node_filters(result, context, scratch)
          .then { |result| instrument_success(result) }
          .rescue do |reason|
            if reason.is_a?(GitHub::Goomba::Reference::StaleReferenceError)
              # Sometimes cached content can be stale. If so don't return, instead re-run the pipeline
              stale_cache(input, original_context, result, cache_settings)
            else
              instrument_failure(reason)
            end
          end
      end

      result[:cache_settings] = cache if context[:cache_settings_in_result]
      html = run_input_filters(input, context, result, scratch)

      sanitizer = context.fetch(:sanitizer, @sanitizer)
      run_node_filters(html, context, result, scratch, sanitizer)
        .then { |html| run_output_filters(html, context, result, scratch) }
        .then do |output|
          result[:output] = output
          cache.set_cached_result(result)
          result
        end
        .then { |result| run_post_cache_node_filters(result, context, scratch) }
        .then { |result| instrument_success(result) }
        .rescue { |reason| instrument_failure(reason) }
    rescue RuntimeError
      # capture failures in synchronous portion of pipeline
      instrument_failure
    end

    def stale_cache(input, context, result, cache_settings)
      GitHub.dogstats.increment("html_pipeline.stale_cache_rerun", tags: ["pipeline:#{dogstats_key}"])
      cache_settings[:skip_cached_results] = true
      async_call!(input, context, result, cache_settings: cache_settings)
    end

    def instrument_success(result)
      GitHub.dogstats.increment("html_pipeline.success", tags: ["pipeline:#{dogstats_key}"])
      result
    end

    def instrument_failure(reason = nil)
      GitHub.dogstats.increment("html_pipeline.failure", tags: ["pipeline:#{dogstats_key}"])
      if reason
        raise reason
      else
        raise
      end
    end

    def preload_flags
      all_filters = @input_filters + @node_filters + @output_filters + @post_cache_node_filters + REFERENCE_FILTERS
      GitHub.flipper.preload(all_filters.flat_map(&:feature_flags).uniq)
    end

    def instantiate_filters(filters, klass, context, result, scratch)
      filters
        .select { |filter| GitHub.instrument("goomba.filter.enabled", filter: filter) { filter.enabled?(context) } }
        .map { |filter| filter.new(context, result, scratch) }
        .each { |filter| raise TypeError, "#{filter} does not inherit from #{klass}" unless filter.is_a?(klass) }
    end

    def run_input_filters(input, context, result, scratch)
      input_filters = instantiate_filters(@input_filters, InputFilter, context, result, scratch)
      input_filters.inject(input) do |text, filter|
        GitHub.instrument "goomba.filter.call", filter: filter do
          filter.call(text)
        end
      end
    end

    def run_node_filters(html, context, result, scratch, sanitizer = nil, node_filters = nil)
      node_filters ||= instantiate_filters(@node_filters, NodeFilter, context, result, scratch)

      doc = Goomba::DocumentFragment.new(html, sanitizer, gather_stats: !!@stats_key)
      result[:html_safe] = true if sanitizer

      # call #scan or #async_scan for all node filters
      scan_results = node_filters.map do |filter|
        if filter.is_a?(Async::NodeFilter)
          filter.async_scan_doc(doc)
        else
          GitHub.instrument "goomba.filter.scan", filter: filter do
            filter.scan(doc)
          end
        end
      end

      Promise.all(scan_results).then do
        # call Goomba::DocumentFragment#to_html, which will call #call for all node filters
        html = GitHub.instrument "goomba.document_fragment.to_html", document: doc do
          doc.to_html(filters: node_filters)
        end

        node_filters.each do |filter|
          filter.finished
        end

        html
      end
    end

    def run_output_filters(html, context, result, scratch)
      output_filters = instantiate_filters(@output_filters, OutputFilter, context, result, scratch)

      # run #call or #async_call for all output filters
      output_filters.reduce(Promise.resolve(html)) do |output_promise, filter|
        output_promise.then do |output|
          if filter.is_a?(AsyncOutputFilter)
            filter.async_call(output)
          else
            GitHub.instrument "goomba.filter.call", filter: filter do
              filter.call(output)
            end
          end
        end
      end
    end

    def run_post_cache_node_filters(result, context, scratch)
      context = context.merge(stage: :post_processing)
      context.freeze

      post_cache_filters = @post_cache_node_filters + REFERENCE_FILTERS
      post_cache_filters = instantiate_filters(post_cache_filters, NodeFilter, context, result, scratch)
      return Promise.resolve(result) unless post_cache_filters.any?

      run_node_filters(result[:output], context, result, scratch, nil, post_cache_filters)
        .then do |html|
          result[:output] = html
          result
        end
    end
  end
end
