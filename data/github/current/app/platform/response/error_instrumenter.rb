# typed: true
# frozen_string_literal: true

module Platform
  class Response
    class ErrorInstrumenter

      class ErrorType < T::Enum
        enums do
          PARSE = new("PARSE")
          RATE_LIMIT = new("RATE_LIMIT")
        end
      end

      class ErrorCode < T::Enum
        enums do
          PLATFORM_PARSE = new("platform_parse")
          GRAPHQL_PARSE = new("graphql_parse")
          GRAPHQL_RATE_LIMIT = new("graphql_rate_limit")
        end
      end

      attr_reader :error, :context, :variables

      def initialize(error, context, variables)
        @error = error
        @context = context
        @variables = variables
      end

      def to_graphql_query_event
        if error.is_a?(GraphQL::ParseError) || error.is_a?(Platform::Errors::Parse)
          # Only Instrument ORIGIN_API atm for Parse errors.
          # Introduced here https://github.com/github/github/pull/105326/commits/7964a86f82f2c07ab708df3ffc7f91341ead167a
          return unless context[:origin] == Platform::ORIGIN_API
        end

        primary_rate_limited = error.is_a?(Platform::Errors::RateLimited)

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
            # When `QueryTracker` was not instantiated for a query, we'll just assign `0`
            # Was implemented on https://github.com/github/github/pull/110675/commits/d4f4093e0130fdce721137fd78cc7396974a6284
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
            spokes_time_ms: 0,
            timed_out: false,
            traffic_mirroring: Api::TrafficMirroring::query_event_value(context),
            metrics_by_service: {},
            primary_rate_limited: primary_rate_limited,
            auth_fingerprint: context[:auth_fingerprint],
          },
        )
      end

      def serialized_errors_for_instrumentation
        raise NotImplementedError, "#{self.class} must implement #serialized_errors_for_instrumentation" # rubocop:disable GitHub/UsePlatformErrors
      end
    end
  end
end
