# typed: true
# frozen_string_literal: true

module Platform
  class GraphqlResponse < Platform::Response
    attr_reader :tracker, :query

    def initialize(query)
      @query = query
      @tracker = query.context[:query_tracker]
      @runtime_errors = query.validation_errors + query.analysis_errors + query.context.errors
      @internal_error = @query.context[:internal_error]
      @instrumenter = Platform::Response::QueryInstrumenter.new(query, internal_error: @internal_error)
    end

    def data
      @query.result["data"]
    end

    def errors
      @errors ||= serialize_errors
    end

    def scrubbed_query_string
      @query.context[:scrubbed_query]
    end

    def extensions
      extensions = {}
      extensions["trace"]    = tracing_result.to_h if tracing_result
      extensions["warnings"] = warnings.to_a if warnings.any?
      extensions["query_owning_catalog_service"] = @query.context[:query_owning_catalog_service] if @errors&.size > 0 && @query&.context[:query_owning_catalog_service]

      extensions
    end

    private

    def allowed_error_fields
      %w{type field path extensions locations message}
    end

    def serialize_errors
      if @internal_error
        [{ "message" => internal_error_message }]
      else
        errors = @runtime_errors.map { |e| serialize_error(e) }
        if tracing_result
          tracing_result.errors.each do |err|
            errors << serialize_error(err)
          end
        end
        errors
      end
    end

    def tracing_result
      if defined?(@tracing_result)
        @tracing_result
      else
        @tracing_result = if @query.context[:performance_trace] && @query.context[:origin] == ORIGIN_API
          perf_tracer = @query.context[:trace]
          PerformancePaneTracer::ExtensionsResult.new(perf_tracer)
        else
          nil
        end
      end
    end

    def serialize_error(error)
      error = error.to_h
      serialized = {}

      allowed_error_fields.each do |allowed|
        serialized[allowed] = error[allowed] if error[allowed]
      end

      serialized
    end

    def internal_error_message
      error_message = "Something went wrong while executing your query."

      if request_id = Rack::RequestId.current
        error_message += " Please include `#{request_id}` when reporting this issue."
      end

      error_message
    end

    def warnings
      @warnings ||= @query.context[:warnings]
    end
  end
end
