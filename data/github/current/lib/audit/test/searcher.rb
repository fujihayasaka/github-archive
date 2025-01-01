# typed: true
# frozen_string_literal: true

module Audit
  module Test
    class Searcher
      class TestIndex
        def name
          "test"
        end
      end

      def index
        @index ||= TestIndex.new
      end

      def generate_index
        index.name
      end

      def perform(options)
        p options
      end
    end
  end
end
