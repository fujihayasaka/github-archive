# typed: true
# frozen_string_literal: true

module Resiliency
  module Responses
    class Set < Response
      def initialize(&block)
        super(::Set.new)
      end
    end
  end
end
