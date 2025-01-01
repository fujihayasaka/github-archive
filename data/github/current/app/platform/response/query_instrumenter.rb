# typed: true
# frozen_string_literal: true

# NOTE: This file has some type annotations in sorbet/rbi/shims/query_instrumenter.rbi

module Platform
  class Response
    class QueryInstrumenter
      def initialize(query, internal_error: nil)
        @query = query
        @validation_errors = query.validation_errors
        @analysis_errors = query.analysis_errors
        @execution_errors = @query.context.errors
        @internal_error = internal_error
      end

      def to_graphql_query_event
        viewer = @query.context[:viewer]

        oauth_app = if viewer && viewer.using_personal_access_token? && viewer.oauth_access
          viewer.oauth_access.safe_app
        else
          @query.context[:oauth_app]
        end

        integration = @query.context[:integration]
        installation = @query.context[:installation]

        schema_version = if @query.context[:target] == :public
          Platform::Schema::PUBLIC_SHA
        else
          Platform::Schema::INTERNAL_SHA
        end

        query_string = @query.context[:scrubbed_query] || @query.context[:query_string]
        query_tracker = @query.context[:query_tracker]

        # Traffic mirroring: For mirrored requests we include a hash and the size of the result
        is_mirrored = @query.context[:is_mirrored_request]
        result_json = is_mirrored ? query_tracker.response.to_json : nil
        result_byte_size = is_mirrored ? result_json.bytesize : nil
        result_hash = is_mirrored ? Platform::Instrumentation::TrackingHash.generate(result_json) : nil

        referrer_controller_action = @query.context[:referrer_controller_action] || nil

        GlobalInstrumenter.instrument(
          Platform::QUERY_EVENT_KEY,
          {
            query_string: query_string,
            app: oauth_app || integration,
            installation: installation,
            viewer: viewer,
            origin: @query.context[:origin],
            target: @query.context[:target],
            schema_version: schema_version,
            dotcom_sha: GitHub.current_sha,
            operation_type:  @query.selected_operation&.operation_type,
            selected_operation: clean_operation_name,
            valid: @query.valid?,
            errors: serialized_errors_for_instrumentation,
            accessed_objects: query_tracker.accessed_objects.values,
            query_hash: query_tracker.query_hash,
            variables_hash: query_tracker.variables_hash,
            cpu_time_ms: query_tracker.clock_times[:cpu].round,
            idle_time_ms: query_tracker.clock_times[:idle].round,
            mysql_count: query_tracker.mysql_count,
            mysql_time_ms: query_tracker.performance_data_total_sql.round,
            gitrpc_count: query_tracker.gitrpc_count,
            gitrpc_time_ms: query_tracker.gitrpc_time_ms.round,
            elastomer_query_count: query_tracker.elastomer_query_count,
            elastomer_query_time_ms: query_tracker.elastomer_query_time_ms.round,
            authzd_batch_authorize_count: query_tracker.authzd_batch_authorize_count,
            authzd_batch_authorize_time_ms: query_tracker.authzd_batch_authorize_time_ms.round,
            timed_out: false,
            node_count: @query.context[:node_count_total],
            request_count: @query.context[:request_count_total],
            complexity_cost: @query.context[:cost_total],
            potential_complexity_cost_with_list_complexity: query_tracker.potential_query_costs.custom_list_complexity,
            potential_complexity_cost_with_corrected_branch_detection: query_tracker.potential_query_costs.corrected_branch_detection,
            potential_list_complexity_node_count_exceeding: query_tracker.potential_query_costs.custom_list_complexity_node_count_exceeding,
            potential_total_node_count_branch_detection: query_tracker.potential_query_costs.total_node_count_branch_detection,
            potential_corrected_parent_request_count: query_tracker.potential_query_costs.corrected_parent_request_count,
            bypass_query_coster_parent_request_count_changes: query_tracker.bypass_query_coster_parent_request_count_changes,
            length_of_largest_alias: query_tracker.length_of_largest_alias,
            fetched_node_id_types: query_tracker.fetched_node_id_types.to_a,
            graphql_global_id_type: @query.context[:graphql_global_id_type],
            graphql_operation_id: query_tracker.operation_id,
            query_byte_size: query_tracker.query_byte_size,
            variables_byte_size: query_tracker.variables_byte_size,
            query_owning_catalog_service: @query.context[:query_owning_catalog_service],
            traffic_mirroring: Api::TrafficMirroring::query_event_value(@query.context), # Traffic mirroring
            result_byte_size: result_byte_size, # Traffic mirroring
            result_hash: result_hash, # Traffic mirroring
            metrics_by_service: CatalogServiceStats.metrics_by_service(@query.context[:trace]),
            primary_rate_limited: query_tracker.rate_limited?,
            auth_fingerprint: @query.context[:auth_fingerprint],
            referrer_controller_action: referrer_controller_action,
            query_depth: @query.context[:query_depth],
          }
        )
      end

      def serialized_errors_for_instrumentation
        serialized_errors = []

        if @internal_error
          serialized_errors << {
            type: "INTERNAL",
            code: @internal_error.class.name.demodulize.downcase.underscore,
            message: @internal_error.to_s,
          }
        end

        @validation_errors.each do |e|
          # Some special cases are from the GraphQL ruby gem (see validation_pipeline.rb
          # in the gem). These get added to the validation_errors array but do not come
          # from a root of StaticValidation::Error hence missing code information.
          code = if e.is_a?(GraphQL::StaticValidation::Error) && e.respond_to?(:code)
            e.code.underscore
          elsif e.is_a? GraphQL::Query::OperationNameMissingError
            "operation_name_missing"
          elsif e.is_a? GraphQL::Query::VariableValidationError
            "variable_validation"
          end

          code ||= e.class.name.demodulize.downcase.underscore

          serialized_errors << {
            type: "VALIDATION",
            code: code,
            message: e.message,
            path: path(e),
            locations: locations(e),
          }
        end

        @analysis_errors.each do |e|
          code = if e.respond_to?(:type)
            e.type.downcase
          else
            e.class.name.demodulize.downcase.underscore
          end

          serialized_errors << {
            type: "ANALYSIS",
            code: code,
            message: e.message,
            path: path(e),
            locations: locations(e),
          }
        end

        @execution_errors.each do |e|
          code = if e.respond_to?(:type)
            e.type.downcase
          else
            e.class.name.demodulize.downcase.underscore
          end

          serialized_errors << {
            type: "EXECUTION",
            code: code,
            message: e.message,
            # Not all errors have a path component - e.g. GraphQL::InvalidNullError
            path: path(e),
            locations: locations(e),
          }
        end

        serialized_errors
      end

      def path(error)
        (error.try(:path) || []).map(&:to_s)
      end

      def locations(error)
        # Locations is a private API on some errors,
        # and sometimes only accessible through `to_h`
        # TODO: fix this in graphql-ruby
        if error.respond_to?(:locations, true)
          error.send(:locations).map(&:stringify_keys)
        else
          (error.to_h["locations"] || []).map(&:stringify_keys)
        end
      end

      def clean_operation_name
        # Some operation names are prefixed with a module name which is difficult to
        # report on (e.g. #<Module:0x00007f7460515b40>__GetSuggestedNavigationDestinations)
        # Strip the prefix!
        name = @query.selected_operation_name
        name.to_s.gsub(/#<Module:0x[0-9a-f]+>__/, "") unless name.nil?
      end
    end
  end
end
