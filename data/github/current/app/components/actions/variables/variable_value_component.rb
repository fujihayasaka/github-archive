# typed: true
# frozen_string_literal: true

module Actions
  module Variables
    class VariableValueComponent < ApplicationComponent
      attr_reader :value

      def initialize(value:)
        @value = value.dup.force_encoding(Encoding::UTF_8)
      end
    end
  end
end
