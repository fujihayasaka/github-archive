# typed: true
# frozen_string_literal: true

module Platform
  class Response
    class ParseErrorInstrumenter
      def initialize(parse_error, context, variables)
        @parse_error = parse_error
        @context = context
        @variables = variables
      end

      def to_graphql_query_event
        # Only Instrument ORIGIN_API for now.
        return unless context[:origin] == Platform::ORIGIN_API

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

        GlobalInstrumenter.instrument(
          Platform::QUERY_EVENT_KEY,
          {
            query_string: query_string,
            app: oauth_app || integration,
            installation: installation,
            viewer: viewer,
            origin: context[:origin],
            target: context[:target],
            schema_version: schema_version,
            dotcom_sha: GitHub.current_sha,
            operation_type:  nil,
            selected_operation: nil,
            valid: false,
            errors: serialized_errors_for_instrumentation,
            accessed_objects: [],
            query_byte_size: query_string.to_s.bytesize,
            variables_byte_size: variables.to_s.bytesize,
            query_hash: Platform::Instrumentation::TrackingHash.generate(query_string || ""), # Can be nil
            variables_hash: Platform::Instrumentation::TrackingHash.generate(variables.to_json),
            # No `QueryTracker` was instantiated for this query, so we'll just call these `0`:
            cpu_time_ms: 0,
            idle_time_ms: 0,
            mysql_count: 0,
            mysql_time_ms: 0,
            gitrpc_count: 0,
            gitrpc_time_ms: 0,
            elastomer_query_count: 0,
            elastomer_query_time_ms: 0,
            authzd_batch_authorize_count: 0,
            authzd_batch_authorize_time_ms: 0,
            timed_out: false,
            traffic_mirroring: Api::TrafficMirroring::query_event_value(context), # Traffic mirroring
            metrics_by_service: {}
          },
        )
      end

      def serialized_errors_for_instrumentation
        [{
          type: "PARSE",
          code: code,
          message: error_message,
          locations: error_locations,
        }]
      end

      private

      attr_reader :parse_error, :context, :variables

      def code
        if parse_error.is_a?(Platform::Errors::Parse)
          "platform_parse"
        else
          "graphql_parse"
        end
      end

      def error_message
        if parse_error.is_a?(Platform::Errors::Parse)
          parse_error.to_s
        else
          parse_error.message
        end
      end

      def error_locations
        if parse_error.is_a?(GraphQL::ParseError) && parse_error.try(:line) && parse_error.try(:col)
          [{ "line" => parse_error.line, "column" => parse_error.col }]
        else
          []
        end
      end
    end
  end
end
