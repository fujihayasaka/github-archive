# typed: strict
# frozen_string_literal: true

# Methods for executing predefined persisted graphql queries identified by id.
module ReactGraphql
  class QueryPreloader
    extend T::Helpers

    sig { params(request: T.nilable(ActionDispatch::Request), current_user: T.nilable(User), controller: ApplicationController).void }
    def initialize(request:, current_user:, controller:)
      @request = request
      @current_user = current_user
      @controller = controller
    end

    sig { params(path_override: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def matching_url_pattern(path_override = nil)
      GitHub.route_query_mapper.get_matching_url_pattern(path_override || @request&.path)
    end

    sig do
      params(
        add_query_time_tags_fn: T.nilable(T.proc.params(arg0: String, arg1: T::Hash[T.untyped, T.untyped]).returns(T.nilable(T::Array[String]))),
        is_hard_navigation: T::Boolean,
        origin: T.untyped,
        path_override: T.nilable(String),
        precompute_subscription_fns: T::Hash[String, T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T.untyped)],
        run_defer_directive: T::Boolean,
        tags: T::Array[String],
        variable_overwrite_fns: T::Hash[Symbol, T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped)]
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def compute_preloaded_queries(
      add_query_time_tags_fn: nil,
      is_hard_navigation: false,
      origin: nil,
      path_override: nil,
      precompute_subscription_fns: {},
      run_defer_directive: false,
      tags: [],
      variable_overwrite_fns: {}
    )
      # check if the current path has matching queries in the routes
      matching_url_pattern = matching_url_pattern(path_override)

      return nil if matching_url_pattern.nil?

      variable_overwrite_fn = variable_overwrite_fns[matching_url_pattern[:url]]
      precompute_subscription_fn = precompute_subscription_fns[matching_url_pattern[:url]]
      preloaded_subscriptions = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))

      preloaded_query_gql_objects = []

      queries = queries_to_preload(matching_url_pattern:)

      execute_preloaded_start = Timer.start
      preloaded_queries = queries.map do |query_id|
        scope = @request&.GET.fetch("scope", nil)
        variables = query_variables(query_id:, matching_url_pattern:, variable_overwrite_fn:)

        result = @controller.execute_query(
          operation_id: query_id,
          variables:,
          performance_trace: false,
          reporting_tags: tags,
          scope:,
          origin:,
          run_defer_directive: run_defer_directive,
          is_hard_navigation: is_hard_navigation,
          add_query_time_tags_fn: add_query_time_tags_fn
        )

        query_timing_data = result.tracker.nil? ? {} : result.tracker.timing_data

        result_hash = result.to_h

        # Dont allow overriding the preloaded_subscriptions
        if !precompute_subscription_fn.nil? && preloaded_subscriptions.blank?
          preloaded_subscriptions = precompute_subscription_fn.call(query_id, result_hash)
        end

        preloaded_query_gql_objects << result

        {
          queryId: query_id,
          queryName: result.query.context[:query_name],
          variables: variables,
          result: result_hash,
          timestamp: Time.now.to_i,
          timing_data: query_timing_data
        }
      end
      execute_preloaded_start.stop

      GitHub.dogstats.distribution("request.ssr.preloaded_queries_execution.time", execute_preloaded_start.elapsed_ms, tags: tags)

      {
        preloaded_queries: preloaded_queries,
        preloaded_subscriptions: preloaded_subscriptions || {},
        preloaded_query_gql_objects: preloaded_query_gql_objects
      }
    end

    private

    sig { params(matching_url_pattern: T::Hash[Symbol, T.untyped]).returns(T::Array[String]) }
    def queries_to_preload(matching_url_pattern:)
      GitHub.route_query_mapper.fetch(matching_url_pattern[:url])
    end

    sig do
      params(
        query_id: String,
        matching_url_pattern: T::Hash[Symbol, T.untyped],
        variable_overwrite_fn: T.nilable(T.proc.params(path_variables: T::Hash[T.untyped, T.untyped]).returns(T.untyped))
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def query_variables(
      query_id:,
      matching_url_pattern:,
      variable_overwrite_fn:
    )
      # get the variables name and types for the current query
      variable_types = GitHub.route_query_mapper.fetch_variables(query_id)

      # map path parameter named captures to their graphql types
      path_variables = {}
      variable_types.each do |variable_name, variable_type|
        next unless matching_url_pattern[:named_captures].key?(variable_name)
        value = matching_url_pattern[:named_captures][variable_name]
        path_variables[variable_name] = case variable_type
        when "Int", "Int!"
          value.to_i
        when "Boolean", "Boolean!"
          value == "true"
        else
          value
        end
      end

      # allow the caller to override the variables as well as add more
      unsorted_variables = if !variable_overwrite_fn.nil?
        variable_overwrite_fn.call(path_variables)
      else
        path_variables
      end

      unsorted_variables.with_indifferent_access.sort_by(&:first).to_h
    end
  end
end
