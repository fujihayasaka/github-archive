# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Results
      class Created < T::Struct
        const :auto_merge_request, AutoMergeRequest

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def serialize = { auto_merge_request_id: auto_merge_request.id }
      end

      class Invalid < T::Struct
        const :reason, Enums::Validations
        const :message, String
      end

      class AlreadyMerged
        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def serialize = {}
      end

      class AlreadyEnqueued < T::Struct
        const :auto_merge_request, T.nilable(AutoMergeRequest)
        const :merge_queue_entry, T.nilable(MergeQueueEntry)

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def serialize = super.transform_values { _1&.id }
      end

      class Error < T::Struct
        const :exception, T.nilable(Exception)
        const :message, String

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def serialize = super.slice("message")
      end
    end
  end
end
