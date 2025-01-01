# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    class Columns < T::Struct
      const :path, T.nilable(String)
      const :commit_id, T.nilable(String)
      const :compressed_diff_hunk, T.nilable(String)
      const :position, T.nilable(Integer)
      const :blob_position, T.nilable(Integer)
      const :blob_path, T.nilable(String)
      const :blob_commit_oid, T.nilable(String)
      const :left_blob, T.nilable(T::Boolean)
      const :outdated, T::Boolean
      const :start_position_offset, T.nilable(Integer)
      const :subject_type, T.nilable(Symbol)
      const :latest_positioning, T.nilable(Positions)

      # Returns a subset of columns that are used for persistence.
      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_attributes
        serialize.compact
      end
    end
  end
end
