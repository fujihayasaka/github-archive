# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    # Wraps an enumerator with readonly replica connections during computation.
    class Readonly < Enumerator
      def initialize(enum, allow_slow_queries: false)
        super() do |results|
          enum = enum.each
          loop do
            results << readonly(allow_slow_queries) { enum.next }
          end
        end
      end

      def readonly(allow_slow_queries = false)
        if allow_slow_queries
          SlowQueryLogger.disabled do
            ActiveRecord::Base.connected_to(role: :reading_slow) { yield }
          end
        else
          ActiveRecord::Base.connected_to(role: :reading) { yield }
        end
      end
    end
  end
end
