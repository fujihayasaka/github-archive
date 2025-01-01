# typed: true
# frozen_string_literal: true

module GitHub
  module Limiters
    class Simple < GitHub::Limiter
      def initialize(name, &block)
        super(name)
        @block = block
      end

      def start(request)
        @block.call(request)
      end
    end
  end
end
