# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # This module defines concrete data structures that capture the different combinations of PullRequestReviewThread
      # column data needed for storing comment positioning information in the database. Each class represents
      # a specific state of the positioning-related columns.
      #
      # Column Categories:
      #   - Immutable: Historical data that never changes once set (original positioning context)
      #   - Diff: Position within diff hunks, can become outdated when commits change
      #   - Blob: Position within file blobs, stable across repositioning operations
      #
      # State Permutations:
      #   - File: DiffFile, BlobFile (comments targeting entire files)
      #   - Line: DiffLine, BlobLine (comments targeting specific lines)
      #   - Outdated: DiffOutdated (comments that can no longer be positioned in current diff)
      #
      module Columns
        # Historical positioning data that never changes once set during comment creation.
        class Immutable < T::Struct
          const :original_commit_id, String
          const :original_position, T.nilable(Integer)
          const :original_base_commit_id, String
          const :original_start_commit_id, String
          const :original_end_commit_id, String
          const :start_position_offset, T.nilable(Integer)
          const :subject_type, Enums::SubjectType
          const :compressed_diff_hunk, T.nilable(String)
          const :left_blob, T::Boolean

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize
        end

        # Represents comments that can no longer be positioned within the current diff. Once outdated, a comment
        # cannot be positioned away from outdated.
        class DiffOutdated < T::Struct
          const :path, T.nilable(String)
          const :commit_id, T.nilable(String)

          sig { returns(T::Boolean) }
          def outdated = true

          sig { returns(T.nilable(Integer)) }
          def position = nil

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize.merge({ "outdated" => outdated, "position" => position })

          sig { returns(DiffOutdated) }
          def as_outdated = self
        end

        # Represents blob columns targeting a specific file on the diff.
        class DiffFile < T::Struct
          const :path, String
          const :outdated, T::Boolean
          const :commit_id, String

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize

          sig { returns(DiffOutdated) }
          def as_outdated = DiffOutdated.new(path:, commit_id:)
        end

        # Represents valid diff hunk positioning on a specific line.
        class DiffLine < T::Struct
          const :path, String
          const :position, Integer
          const :outdated, T::Boolean
          const :commit_id, String

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize

          sig { returns(DiffOutdated) }
          def as_outdated = DiffOutdated.new(path:, commit_id:)
        end

        Diffs = T.type_alias { T.any(DiffLine, DiffFile, DiffOutdated) }

        # Represents valid blob position data targeting a specific line. This position value is 0-indexed.
        class BlobLine < T::Struct
          const :blob_position, Integer
          const :blob_path, String
          const :blob_commit_oid, String

          # 1-indexed version of blob_position.
          sig { returns(Integer) }
          def line = blob_position.next

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize
        end

        # Represents valid blob position data targeting a specific file.
        class BlobFile < T::Struct
          const :blob_path, String
          const :blob_commit_oid, String

          sig { returns(T::Hash[String, T.untyped]) }
          def to_database_columns = serialize
        end

        Blobs = T.type_alias { T.any(BlobLine, BlobFile) }
      end
    end
  end
end
