# typed: true
# frozen_string_literal: true

module Mocks
  module GitHub
    class Features
      def initialize
        @features = {}
      end

      def [](key)
        @features[key] ||= Feature.new(key, enabled: false)
      end
    end
  end
end
