# typed: true
# frozen_string_literal: true

module Api
  module Serializer
    module CodeownersDependency
      def codeowners_error_list(data, options)
        errors = data[:errors]
        path = data[:path]

        { errors: errors.map { |error| codeowners_error(error, path) } }
      end

      private

      def codeowners_error(error, path)
        {
          line: error.line,
          column: error.column,
          source: error.source,
          kind: error.kind,
          suggestion: error.suggestion,
          message: error.message,
          path: path,
        }
      end
    end
  end
end
