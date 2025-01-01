# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class MissingBackwardsPaginationArgument < GraphQL::AnalysisError
      def initialize(field, ast_node: nil)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        message = "Backwards pagination requires a `before` cursor to paginate #{phrase}."
        super(message, ast_node: ast_node)
      end
    end
  end
end
