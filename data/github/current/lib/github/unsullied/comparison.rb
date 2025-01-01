# typed: true
# frozen_string_literal: true

module GitHub
  module Unsullied
    class Comparison
      attr_accessor :wiki, :older, :newer

      def initialize(wiki, older, newer)
        @wiki  = wiki
        @older = older
        @newer = newer
      end
    end
  end
end
