# typed: true
# frozen_string_literal: true

module GitHub
  module Throttler

    # The Null throttler. Does nothing.
    class Null
      def initialize(*opts)
      end

      def throttle(*)
        yield
      end
    end
  end
end
