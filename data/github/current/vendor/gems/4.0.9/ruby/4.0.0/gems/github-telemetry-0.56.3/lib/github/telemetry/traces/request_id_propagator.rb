# frozen_string_literal: true

module GitHub
  module Telemetry
    module Traces
      class RequestIDPropagator
        REQUEST_ID_KEY = "X-Request-Id"
        REQUEST_ID_CONTEXT_KEY = OpenTelemetry::Context.create_key(REQUEST_ID_KEY)

        GITHUB_REQUEST_ID_KEY = "X-GitHub-Request-Id"
        GITHUB_REQUEST_ID_CONTEXT_KEY = OpenTelemetry::Context.create_key(GITHUB_REQUEST_ID_KEY)

        FIELDS = [REQUEST_ID_KEY, GITHUB_REQUEST_ID_KEY].freeze

        # Injects x-request-id and x-github-request-id into the carrier.
        #
        # The injected value for x-request-id will be taken from the context if it
        # exists. If it does not exist, the value will be the trace ID.
        #
        # The x-github-request-id value will be set to one of the following, in order of preference:
        #  - an existing value on the carrier, if it exists and can be read (for backwards compatibility)
        #  - the existing x-github-request-id value if it exists
        #  - the trace ID if x-github-request-id doesn't exist
        #  - a random UUID as a fallback, if tracing is not setup
        #
        # @param [Carrier] carrier The mutable carrier to inject trace context into
        # @param [Context] context The context to read trace context from
        # @param [optional Setter] setter If the optional setter is provided, it
        #   will be used to write context into the carrier, otherwise the default
        #   text map setter will be used.
        def inject(carrier, context: OpenTelemetry::Context.current, setter: OpenTelemetry::Context::Propagation.text_map_setter)
          github_request_id = get_from_carrier(carrier, GITHUB_REQUEST_ID_KEY) || context.value(GITHUB_REQUEST_ID_CONTEXT_KEY) || trace_id_or_fallback(context)
          setter.set(carrier, GITHUB_REQUEST_ID_KEY, github_request_id)

          request_id = context.value(REQUEST_ID_CONTEXT_KEY)
          if request_id && !request_id.empty?
            setter.set(carrier, REQUEST_ID_KEY, request_id)
          else
            span_context = OpenTelemetry::Trace.current_span(context).context
            return unless span_context.valid?
            setter.set(carrier, REQUEST_ID_KEY, span_context.hex_trace_id)
          end
        end

        # Extracts the x-request-id and x-github-request-id headers from the supplied carrier, and sets them in the context. If extraction fails,
        # the context is returned unchanged.
        #
        # @param [Carrier] carrier The carrier to extract the request IDs from
        # @param [optional Context] context The context to set the request IDs in. Defaults to Context.current
        # @param [optional TextMapGetter] getter The getter to use to extract the request IDs
        #   Defaults to OpenTelemetry::Context::Propagation.text_map_getter
        #
        # @return [Context] The context with the request ID and github request ID set, or the original context if extraction fails
        def extract(carrier, context: OpenTelemetry::Context.current, getter: OpenTelemetry::Context::Propagation.text_map_getter)
          github_request_id = getter.get(carrier, GITHUB_REQUEST_ID_KEY)
          request_id = getter.get(carrier, REQUEST_ID_KEY)

          new_context = context
          new_context = new_context.set_value(GITHUB_REQUEST_ID_CONTEXT_KEY, github_request_id) if github_request_id
          new_context = new_context.set_value(REQUEST_ID_CONTEXT_KEY, request_id) if request_id
          new_context
        end

        def trace_id_or_fallback(context)
          span = OpenTelemetry::Trace.current_span(context)
          if span.context.valid?
            span.context.hex_trace_id
          else
            SecureRandom.uuid
          end
        end

        def get_from_carrier(carrier, field)
          return nil unless carrier && carrier.respond_to?(:[])
          carrier[field]
        end

        # Returns the predefined propagation fields.
        #
        # @return [Array<String>] a list of fields that will be used by this propagator.
        def fields
          FIELDS
        end
      end
    end
  end
end
