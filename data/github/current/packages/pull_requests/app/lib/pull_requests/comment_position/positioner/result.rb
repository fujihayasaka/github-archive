# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      class Result < T::Struct
        # The resulting position value.
        const :positioning, Positions
        const :previous_positioning, T.nilable(Positions)
        const :original_positioning, T.nilable(Positions)
        alias latest_positioning positioning

        # Column values for the PullRequestReviewThread.
        const :immutable_columns, T.nilable(Columns::Immutable)
        const :diff_columns, T.nilable(Columns::Diffs)
        const :blob_columns, T.nilable(Columns::Blobs)

        sig { returns(String) }
        def base_commit_oid = positioning.base_commit_oid

        sig { returns(String) }
        def head_commit_oid = positioning.head_commit_oid

        sig { params(without: T.any(T::Array[Symbol], Symbol)).returns(HashWithIndifferentAccess) }
        def to_database_columns(without: [])
          { immutable_columns:, diff_columns:, blob_columns: }
            .except(*Array.wrap(without))
            .values
            .compact
            .map(&:to_database_columns)
            .reduce(HashWithIndifferentAccess.new(
              original_positioning: original_positioning&.serialize,
              latest_positioning: latest_positioning.serialize,
            ).compact, &:merge)
        end
      end
    end
  end
end
