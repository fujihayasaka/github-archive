# typed: true
# frozen_string_literal: true

module Platform
  class Response
    class ParseErrorInstrumenter < ErrorInstrumenter
      def serialized_errors_for_instrumentation
        [{
          type: ErrorInstrumenter::ErrorType::PARSE.serialize,
          code: code,
          message: error_message,
          locations: error_locations,
        }]
      end

      private

      def code
        if error.is_a?(Platform::Errors::Parse)
          ErrorInstrumenter::ErrorCode::PLATFORM_PARSE.serialize
        else
          ErrorInstrumenter::ErrorCode::GRAPHQL_PARSE.serialize
        end
      end

      def error_message
        if error.is_a?(Platform::Errors::Parse)
          error.to_s
        else
          error.message
        end
      end

      def error_locations
        if error.is_a?(GraphQL::ParseError) && error.try(:line) && error.try(:col)
          [{ "line" => error.line, "column" => error.col }]
        else
          []
        end
      end
    end
  end
end
