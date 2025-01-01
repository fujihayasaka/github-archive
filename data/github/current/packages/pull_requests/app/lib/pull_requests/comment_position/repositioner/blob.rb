# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Structure describing the location of a specific blob within git and the diff range used when generating it.
      class Blob < T::Struct

        # Rollup state encapsulating all the states the blob falls in to.
        class State < T::Enum
          enums do
            Current = new(:current) # This blob was loaded from the database and/or request.
            Repositioned = new(:repositioned) # The blob was successfully repositioned.
            NotRequested = new(:not_requested) # This blob was never requested to reposition.
            RemovedLine = new(:removed_line) # The line could not be repositioned in the target tree.
            RemovedPath = new(:removed_path) # The path was deleted in the target tree.
            InvalidPath = new(:invalid_path) # The path does not exist in the source tree.
            ContentTooLarge = new(:content_too_large) # API limitation on blob sizes.
            Unknown = new(:unknown) # Unknown/fallback error.
          end
        end

        const :state, State
        const :path, T.nilable(String)
        const :commit_oid, String
        const :line, T.nilable(Integer)
        const :source_base_commit_oid, String
        const :source_head_commit_oid, String
        const :target_base_commit_oid, String
        const :target_head_commit_oid, String

        sig { returns(T::Boolean) }
        def left? = commit_oid == source_base_commit_oid

        sig { returns(T::Boolean) }
        def up_to_date? = commit_oid == target_commit_oid

        sig { returns(T::Boolean) }
        def out_of_date? = !up_to_date?

        sig { returns(String) }
        def target_commit_oid = left? ? target_base_commit_oid : target_head_commit_oid

        sig { params(state: State, commit_oid: String, path: T.nilable(String), line: T.nilable(Integer)).returns(Blob) }
        def with(state:, commit_oid:, path:, line:)
          Blob.new(
            state:, commit_oid:, path:, line:,
            source_base_commit_oid:, source_head_commit_oid:, target_base_commit_oid:, target_head_commit_oid:
          )
        end

        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          case other
          when Blob then serialize == other.serialize
          else super
          end
        end
      end
    end
  end
end
