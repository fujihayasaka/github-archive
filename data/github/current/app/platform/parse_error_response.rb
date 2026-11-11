# typed: true
# frozen_string_literal: true

module Platform
  class ParseErrorResponse < Platform::Response
    attr_reader :context

    def initialize(parse_error, provided_context: {}, provided_variables: nil)
      if !parse_error.is_a?(GraphQL::ParseError) && !parse_error.is_a?(Platform::Errors::Parse)
        raise ArgumentError, "Invalid error type for ParseErrorResponse: #{parse_error}" # rubocop:disable GitHub/UsePlatformErrors
      end

      @parse_error = parse_error
      @instrumenter = Platform::Response::ParseErrorInstrumenter.new(parse_error, provided_context, provided_variables)
    end

    def errors
      @errors ||= serialize_errors
    end

    private

    def serialize_errors
      if parse_error.is_a?(GraphQL::ParseError)
        error = { "message" => parse_error.message }

        if parse_error.try(:line) && parse_error.try(:col)
          error["locations"] = [{ "line" => parse_error.line, "column" => parse_error.col }]
        end

        [error]
      elsif parse_error.is_a?(Platform::Errors::Parse)
        [{ "message" => parse_error.to_s }]
      end
    end

    attr_reader :parse_error
  end
end
