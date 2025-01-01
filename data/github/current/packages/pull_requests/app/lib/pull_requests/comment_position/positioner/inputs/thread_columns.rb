# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Inputs
        # Existing thread column values from the database.
        class ThreadColumns < T::Struct
          const :base_commit_oid, String
          const :head_commit_oid, String
          const :original_positioning, T.nilable(Positions)
          const :latest_positioning, T.nilable(Positions)
          const :identifier, Integer
          const :path, T.nilable(String)
          const :commit_id, T.nilable(String)
          const :position, T.nilable(Integer)
          const :blob_position, T.nilable(Integer)
          const :blob_path, T.nilable(String)
          const :blob_commit_oid, T.nilable(String)
          const :left_blob, T::Boolean
          const :outdated, T::Boolean
          const :start_position_offset, T.nilable(Integer)
          const :subject_type, Enums::SubjectType
          const :original_commit_id, T.nilable(String)
          const :original_position, T.nilable(Integer)
          const :original_base_commit_id, T.nilable(String)
          const :original_start_commit_id, T.nilable(String)
          const :original_end_commit_id, T.nilable(String)
          const :compressed_diff_hunk, T.nilable(String)

          sig { returns(Enums::Side) }
          def side = left_blob ? Enums::Side::Left : Enums::Side::Right
        end
      end
    end
  end
end
