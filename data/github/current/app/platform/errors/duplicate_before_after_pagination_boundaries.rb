# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class DuplicateBeforeAfterPaginationBoundaries < GraphQL::AnalysisError
      def initialize(field = nil, ast_node: nil)
        phrase = field.nil? ? "the connection" : "the `#{field.name}` connection"
        super("Passing both `before` and `after` values, to paginate #{phrase} is not supported.", ast_node: ast_node)
      end
    end
  end
end
