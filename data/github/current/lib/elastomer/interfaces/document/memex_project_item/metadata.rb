# typed: strict
# frozen_string_literal: true

require_relative "./timestamp_helper"

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Metadata < T::Struct
          include Elastomer::Interfaces::Document::MemexProjectItem::TimestampHelper

          # Though created_at and updated_at are not nullable at the database level, they are `T.nilable`
          # because they will be nil for unsaved objects.
          const :created_at, T.nilable(String)
          const :updated_at, T.nilable(String)
          const :id, Integer
          const :memex_project_id, Integer
          const :creator_id, Integer
          const :virtual_priority, T.nilable(String)
          const :archived_at, T.nilable(String)

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def to_hash
            {
              database_id: id,
              memex_project_id: memex_project_id,
              creator_id: creator_id,
              virtual_priority: virtual_priority,
              archived_at: safe_iso8601(archived_at),
              created_at:  safe_iso8601(created_at),
              updated_at: safe_iso8601(updated_at),
            }
          end
        end
      end
    end
  end
end
