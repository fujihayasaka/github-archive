# typed: true
# frozen_string_literal: true

module Resiliency
  module Responses
    class Count < Response
      def initialize(&block)
        super(0)
      end

      def count
        value
      end
    end
  end
end
