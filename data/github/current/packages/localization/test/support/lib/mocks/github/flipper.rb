# typed: true
# frozen_string_literal: true

# this mocks the GitHub class so we can easily sync the code from and to GH
module Mocks
  module GitHub
    class Flipper
      def initialize
        @features = Features.new
      end

      def reset
        @features = Features.new
      end

      def [](key)
        @features[key]
      end
    end
  end
end
