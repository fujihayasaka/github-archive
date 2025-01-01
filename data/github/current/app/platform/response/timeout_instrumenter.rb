# typed: true
# frozen_string_literal: true

module Platform
  class Response
    # A Timeout instrumenter made to be notified by GitHub::TimeoutMiddleware.
    # This should not be used in any other context than within a
    # GitHub::TimeoutMiddleware.notify context, and assumes the process exits
    # After the instrumentation. This is a last resort instrumentation to help debugging timed out queries.
    class TimeoutInstrumenter
      sig { params(query: GraphQL::Query).void }
      def initialize(query)
        @query = query
      end

      def timeout(env)
        context = @query.context
        report_persisted_query_timeout

        # Only Instrument ORIGIN_API for now.
        return unless context[:origin] == Platform::ORIGIN_API

        request_context = context[:request_context]
        viewer = context[:viewer]

        oauth_app = if viewer && viewer.using_personal_access_token?
          viewer.oauth_access.safe_app
        else
          context[:oauth_app]
        end

        integration = context[:integration]
        installation = context[:installation]

        schema_version = if context[:target] == :public
          Platform::Schema::PUBLIC_SHA
        else
          Platform::Schema::INTERNAL_SHA
        end

        query_string = context[:scrubbed_query] || context[:query_string]
        query_tracker = @query.context[:query_tracker]

        GlobalInstrumenter.instrument(
          Platform::QUERY_EVENT_KEY,
          {
            request_context: request_context,
            query_string: query_string,
            app: oauth_app || integration,
            installation: installation,
            viewer: viewer,
            origin: @query.context[:origin],
            target: @query.context[:target],
            schema_version: schema_version,
            dotcom_sha: GitHub.current_sha,
            operation_type:  @query.selected_operation&.operation_type,
            selected_operation: @query.selected_operation_name,
            valid: @query.valid?,
            errors: [],
            accessed_objects: query_tracker.accessed_objects.values,
            query_hash: query_tracker.query_hash,
            variables_hash: query_tracker.variables_hash,
            cpu_time_ms: clock_times[:cpu].round,
            idle_time_ms: clock_times[:idle].round,
            mysql_count: query_tracker.mysql_count,
            mysql_time_ms: query_tracker.performance_data_total_sql.round,
            gitrpc_count: gitrpc_count,
            gitrpc_time_ms: gitrpc_time.round,
            elastomer_query_count: query_tracker.elastomer_query_count,
            elastomer_query_time_ms: query_tracker.elastomer_query_time_ms.round,
            authzd_batch_authorize_count: query_tracker.authzd_batch_authorize_count,
            authzd_batch_authorize_time_ms: query_tracker.authzd_batch_authorize_time_ms.round,
            timed_out: true,
            node_count: @query.context[:node_count_total],
            complexity_cost: @query.context[:cost_total],
            request_id: request_context[:request_id],
            operation_id: request_context[:operation_id],
            query_byte_size: query_tracker.query_byte_size,
            variables_byte_size: query_tracker.variables_byte_size,
            query_owning_catalog_service: @query.context[:query_owning_catalog_service],
            traffic_mirroring: Api::TrafficMirroring::query_event_value(@query.context), # Traffic mirroring
            metrics_by_service: CatalogServiceStats.metrics_by_service(@query.context[:trace]),
            primary_rate_limited: query_tracker.rate_limited?,
            auth_fingerprint: context[:auth_fingerprint],
          },
        )
      end

      private

      def report_persisted_query_timeout
        return unless @query.context[:operation_id]
        tags = []
        tags += @query.context[:reporting_tags] if @query.context[:reporting_tags]
        tags << "operation_type:#{QueryTracker.operation_type_name(@query)}"
        tags << "operation_name:#{@query.context[:query_name]}" if @query.context[:query_name]
        tags << "gql_operation_name:#{@query.context[:query_name]}" if @query.context[:query_name]
        tags << "query_owning_catalog_service:#{@query.context[:query_owning_catalog_service]}" if @query.context[:query_owning_catalog_service]

        GitHub.dogstats.increment("request.timeout.persisted_queries.count", tags: tags)
      end

      def clock_times
        real_start = @query.context[:query_tracker].real_start
        cpu_start = @query.context[:query_tracker].cpu_start

        if real_start && cpu_start
          real = Process.clock_gettime(Process::CLOCK_MONOTONIC) - real_start
          cpu  = Process.clock_gettime(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu_start

          {
            cpu: cpu * 1000,
            idle: (real - cpu) * 1000,
          }
        else
          {
            cpu: 0,
            idle: 0,
          }
        end
      end

      def gitrpc_count
        gitrpc_before_count = query_tracker.gitrpc_before_count

        if gitrpc_before_count
          GitRPCLogSubscriber.rpc_count - gitrpc_before_count
        else
          0
        end
      end

      def gitrpc_time
        gitrpc_before_time = query_tracker.gitrpc_before_time

        if gitrpc_before_time
          (GitRPCLogSubscriber.rpc_time - gitrpc_before_time) * 1000
        else
          0
        end
      end

      def query_tracker
        @query.context[:query_tracker]
      end
    end
  end
end
