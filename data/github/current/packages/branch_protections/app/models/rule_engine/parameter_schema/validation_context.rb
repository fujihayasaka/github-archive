# typed: true
# frozen_string_literal: true

module RuleEngine
  module ParameterSchema
    class ValidationContext

      attr_reader :root
      attr_reader :parent

      def initialize(root, parent)
        @root = root
        @parent = parent
      end
    end
  end
end
