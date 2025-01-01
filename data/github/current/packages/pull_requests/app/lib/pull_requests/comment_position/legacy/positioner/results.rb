# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        module Results
          extend T::Helpers
          include Kernel

          sealed!

          class Columns < T::Struct
            include Results

            const :path, T.nilable(String)
            const :commit_id, T.nilable(String)
            const :compressed_diff_hunk, T.nilable(String)
            const :position, T.nilable(Integer)
            const :blob_position, T.nilable(Integer)
            const :blob_path, T.nilable(String)
            const :blob_commit_oid, T.nilable(String)
            const :left_blob, T::Boolean
            const :outdated, T::Boolean
            const :start_position_offset, T.nilable(Integer)
            const :subject_type, Symbol
          end

          class Failed < T::Struct
          end
        end
      end
    end
  end
end
