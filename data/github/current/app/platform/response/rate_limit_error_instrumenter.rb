# typed: true
# frozen_string_literal: true

module Platform
  class Response
    class RateLimitErrorInstrumenter < ErrorInstrumenter

      def serialized_errors_for_instrumentation
        [{
          type: ErrorInstrumenter::ErrorType::RATE_LIMIT.serialize,
          code: ErrorInstrumenter::ErrorCode::GRAPHQL_RATE_LIMIT.serialize,
          message: error.message,
        }]
      end
    end
  end
end
