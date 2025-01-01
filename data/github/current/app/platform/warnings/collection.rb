# typed: true
# frozen_string_literal: true

module Platform
  module Warnings
    class Collection
      def initialize
        @warnings = []
      end

      def add(object)
        @warnings << object
      end

      def to_a
        @warnings.map(&:to_h)
      end

      def any?
        @warnings.any?
      end
    end
  end
end
