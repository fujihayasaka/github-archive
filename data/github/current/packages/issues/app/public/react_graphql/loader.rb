# typed: strict
# frozen_string_literal: true

module ReactGraphql
  # `ReactGraphql::Loader` manages GraphQL data-fetching for React apps being rendered. It depends on
  # the `PersistedGraphqlQueryDependency` and `DeferredQueryHelper` being available in the `helpers` param.
  class Loader
    include Platform::Helpers::DeferredQueryHelper

    sig do
      params(
        add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
        controller: ApplicationController,
        origin: T.untyped,
        path_override: T.nilable(String),
        precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        query_callback_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        request: ActionDispatch::Request,
        run_async_with_defer: T::Boolean,
        stats: T::Hash[Symbol, T.untyped],
        tags: T::Array[String],
        user: T.nilable(User),
        variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)]
      ).void
    end
    def initialize(
      add_query_time_tags_fn:,
      controller:,
      origin:,
      path_override:,
      precompute_subscription_fns:,
      query_callback_fns:,
      request:,
      run_async_with_defer:,
      stats:,
      tags:,
      user:,
      variable_overwrite_fns:
    )
      @add_query_time_tags_fn = add_query_time_tags_fn
      @controller = controller
      @origin = origin
      @path_override = path_override
      @precompute_subscription_fns = precompute_subscription_fns
      @query_callback_fns = query_callback_fns
      @request = request
      @run_async_with_defer = run_async_with_defer
      @stats = stats
      @tags = tags
      @variable_overwrite_fns = variable_overwrite_fns

      @query_preloader = T.let(
        ReactGraphql::QueryPreloader.new(
          current_user: user,
          request: request,
          controller: controller
        ),
        ReactGraphql::QueryPreloader
      )

      @trackers = T.let({}, T::Hash[Symbol, T.untyped])
    end

    # Public: Preloads GraphQL data using the `PersistedGraphqlQueryDependency` helper. If any data is loaded
    # it will be injected into `ssr_payload[:data][:payload][:preloadedQueries]` and
    # `ssr_payload[:data][:payload][:preloadedSubscriptions]`. The data can also be deferred
    # if `@run_async_with_defer` is set.
    sig { params(ssr_payload: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def preload(ssr_payload:)
      preload_data_timer = Timer.start
      # TODO: stop using helpers, https://github.com/github/web-systems/issues/2142
      preloaded_data = @query_preloader.compute_preloaded_queries(
        variable_overwrite_fns: @variable_overwrite_fns,
        tags: @tags,
        path_override: @path_override,
        precompute_subscription_fns: @precompute_subscription_fns,
        add_query_time_tags_fn: @add_query_time_tags_fn,
        origin: @origin,
        run_defer_directive: @run_async_with_defer,
        is_hard_navigation: true
      )

      @stats[:preload_data_duration] = preload_data_timer.elapsed_ms

      update_ssr_payload_with_preloaded_data(preloaded_data: preloaded_data, ssr_payload: ssr_payload)

      # cleanup
      if preloaded_data.present?
        @stats[:query_timings] = []
        preloaded_data[:preloaded_queries].each do |query|
          @stats[:query_timings] << query[:timing_data].to_h
          query.delete(:timing_data)
        end
      end

      preloaded_data
    end

    # Public: Loads @defer GraphQL data using the `DeferredQueryHelper` and updates `ssr_payload[:data][:payload][:preloadedSubscriptions]`.
    sig { params(preloaded_data: T.nilable(T::Hash[Symbol, T.untyped]), ssr_payload: T::Hash[Symbol, T.untyped]).returns(Integer) }
    def compute_deferred_data(preloaded_data:, ssr_payload:)
      defer_duration = 0

      if preloaded_data.present?
        defer_data_timer = Timer.start

        execute_deferrals(preloaded_data: preloaded_data, ssr_payload: ssr_payload)

        defer_duration = defer_data_timer.elapsed_ms
        @stats[:defer_data_duration] = defer_duration
      end

      @stats[:query_deferred_timing_data] = deferred_timing_data

      defer_duration
    end

    private

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def deferred_timing_data
      query_deferred_timing_data = []
      @trackers.each do |_, tracker|
        next if tracker.nil?
        tracker.deferred_fragment_trackers.each do |deferred_tracker|
          deferred_fragment_timing_data = deferred_tracker.timing_data
          deferred_fragment_timing_data["defer_label"] = deferred_tracker.defer_label
          deferred_fragment_timing_data["type"] = deferred_tracker.execution_type
          deferred_fragment_timing_data["streamed_chunks_count"] = deferred_tracker.streamed_chunks_count
          query_deferred_timing_data << deferred_fragment_timing_data
        end
      end
      query_deferred_timing_data
    end

    sig { params(preloaded_data: T.nilable(T::Hash[Symbol, T.untyped]), ssr_payload: T::Hash[Symbol, T.untyped]).void }
    def update_ssr_payload_with_preloaded_data(preloaded_data:, ssr_payload:)
      if !preloaded_data.nil? && preloaded_data[:preloaded_queries].length > 0
        ssr_payload[:data][:payload] ||= {}
        ssr_payload[:data][:payload][:preloadedQueries] = preloaded_data[:preloaded_queries]
        # do only precompute if we have all data if we execute the a query with a defer directive it might not have all the data yet
        ssr_payload[:data][:payload][:preloadedSubscriptions] = preloaded_data[:preloaded_subscriptions] unless @run_async_with_defer
      end
    end

    sig { params(preloaded_data: T::Hash[Symbol, T.untyped], ssr_payload: T::Hash[Symbol, T.untyped]).void }
    def execute_deferrals(preloaded_data:, ssr_payload:)
      matching_url = @query_preloader.matching_url_pattern(@path_override)&.[](:url)
      precompute_subscription_fn = matching_url ? @precompute_subscription_fns[matching_url] : nil
      query_callback_fn = matching_url ? @query_callback_fns[matching_url] : nil

      preloaded_data[:preloaded_queries].each_with_index do |query, index|
        gql_query_object = preloaded_data[:preloaded_query_gql_objects][index].query
        tracker = preloaded_data[:preloaded_query_gql_objects][index].tracker
        # deep dup the data so we don't reset it if an execution error occurs
        result_data = query[:result]["data"].deep_dup
        # execute the deferrals and inject the data into the initial data
        query[:result]["data"] = execute_deferral_for_query(gql_query_object, result_data)
        @trackers[gql_query_object.context[:query_name]] = tracker unless tracker.nil?

        if !ssr_payload[:data][:payload][:preloadedSubscriptions] && precompute_subscription_fn
          ssr_payload[:data][:payload][:preloadedSubscriptions] = precompute_subscription_fn.call(query[:queryId], query[:result]) || {}
        end
        query_callback_fn&.call(query[:queryId], query[:result])
      end
    end
  end
end
