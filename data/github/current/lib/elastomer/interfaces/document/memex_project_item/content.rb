# typed: strict
# frozen_string_literal: true

require_relative "./timestamp_helper"

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Content < T::Struct
          include Elastomer::Interfaces::Document::MemexProjectItem::TimestampHelper

          const :id, Integer
          const :type, ::MemexProjectItem::ContentType
          const :number, T.nilable(Integer)
          const :repository_id, T.nilable(Integer)
          const :user_id, T.nilable(Integer)
          const :closed_at, T.nilable(String)
          const :created_at, T.nilable(String)
          # List of issues that are blocking this content (open or closed)
          const :blocked_by, T.nilable(T::Array[DependencyIssue])
          # List of issues that this content is blocking (open or closed)
          const :blocking, T.nilable(T::Array[DependencyIssue])
          # Count of open "blocked by" relationships
          const :open_blocked_by_count, T.nilable(Integer)
          # Count of open blocking relationships
          const :open_blocking_count, T.nilable(Integer)

          prop :state, ContentState
          prop :state_reason, T.nilable(IssueStateReason)
          prop :is_draft, T::Boolean, default: false

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              id: id,
              type: type.serialize,
              state: state.serialize,
              state_reason: state_reason&.serialize,
              open_blocked_by_count: open_blocked_by_count,
              blocked_by: blocked_by&.map(&:to_hash),
              open_blocking_count: open_blocking_count,
              blocking: blocking&.map(&:to_hash),
              is_draft: is_draft,
              number: number,
              repository_id: repository_id,
              user_id: user_id,
              closed_at: safe_iso8601(closed_at),
              created_at: safe_iso8601(created_at),
            }
          end
        end
      end
    end
  end
end
