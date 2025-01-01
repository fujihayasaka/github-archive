# typed: false
# frozen_string_literal: true

module GitHub
  module Cache
    class FakeResponse
      attr_reader :key, :value

      def initialize(key:, value:, exists: false, stored: false)
        @key = key
        @value = value
        @exists = exists
        @stored = stored
      end

      def exist?
        @exists
      end

      def stored?
        @stored
      end
    end
  end
end
