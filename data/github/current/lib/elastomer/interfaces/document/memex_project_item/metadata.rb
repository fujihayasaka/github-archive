# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Metadata < T::Struct
          extend T::Sig

          # Though created_at and updated_at are not nullable at the database level, they are `T.nilable`
          # because they will be nil for unsaved objects.
          const :created_at, T.nilable(String)
          const :updated_at, T.nilable(String)
          const :id, Integer
          const :memex_project_id, Integer
          const :virtual_priority, T.nilable(String)
          const :archived_at, T.nilable(String)

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              database_id: id,
              memex_project_id: memex_project_id,
              virtual_priority: virtual_priority,
              archived_at: safe_iso8601(archived_at),
              created_at:  safe_iso8601(created_at),
              updated_at: safe_iso8601(updated_at),
            }
          end

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
