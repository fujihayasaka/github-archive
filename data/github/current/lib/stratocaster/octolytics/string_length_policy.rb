# typed: true
# frozen_string_literal: true

module Stratocaster
  module Octolytics
    # Enforces a maximum length on strings in an event. Real data exists
    # where, for instance, commit messages are saved as the entire diff of a
    # change. These diffs might be several megabytes, longer than is useful
    # for most analytics. Without being chopped to a more reasonable length,
    # these messages may cause problems downstream as they will be slow to
    # deserialize, clog the message queue, and encur storage costs.
    class StringLengthPolicy
      attr_reader :truncated

      def initialize(event, max_length: 65536)
        @event = event
        @max_length = max_length
      end

      def enforce
        @truncated = false

        enforce_object(@event)
      end

      private

      def enforce_object(object)
        case object
        when String
          if object.length <= @max_length
            object
          else
            @truncated = true
            object.slice(0, @max_length)
          end
        when Hash
          Hash[object.map { |k, v| [k, enforce_object(v)] }]
        when Enumerable
          object.map { |v| enforce_object(v) }
        else
          object
        end
      end
    end
  end
end
