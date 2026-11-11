# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class MaxAliasSizeExceeded < Errors::Analysis
      def initialize(message, ast_node: nil)
        super("MAX_ALIAS_SIZE_EXCEEDED", message, ast_node: ast_node)
      end

    end
  end
end
