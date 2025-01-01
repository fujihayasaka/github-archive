# typed: true
# frozen_string_literal: true

module Resiliency
  module Responses
    class Boolean < Response
      def initialize(&block)
        super(false)
      end

      def value?
        @value
      end
    end
  end
end
