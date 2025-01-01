# typed: true
# frozen_string_literal: true

module Resiliency
  module Responses
    class Array < Response
      def initialize(&block)
        super([])
      end
    end
  end
end
