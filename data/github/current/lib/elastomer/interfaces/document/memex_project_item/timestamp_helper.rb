# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        module TimestampHelper
          # This method is used to ensure that timestamps are in ISO8601 format. This is necessary because the
          # the Search::MemexProjectItemReconciler will view them as different if one is in ISO8601 format and the other is not.
          # If the timestamp string is not parseable, it is returned as-is.
          sig { params(timestamp: T.nilable(String)).returns(T.nilable(String)) }
          private def safe_iso8601(timestamp)
            return unless timestamp

            Time.parse(timestamp).utc.iso8601 # converting a UTC time to UTC is a no-op
          rescue ArgumentError
            timestamp
          end
        end
      end
    end
  end
end
