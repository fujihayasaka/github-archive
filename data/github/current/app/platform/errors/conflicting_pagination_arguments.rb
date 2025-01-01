# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ConflictingPaginationArguments < GraphQL::AnalysisError
      def initialize(field, ast_node: nil)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super("Passing both `after` and `numericPage` values to paginate #{phrase} is not supported.", ast_node: ast_node)
      end
    end
  end
end
