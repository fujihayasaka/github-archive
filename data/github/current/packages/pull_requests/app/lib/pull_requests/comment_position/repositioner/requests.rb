# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Structures describing the Positional request data from various locations such as PullRequestReviewThread.
      module Requests
        extend T::Helpers

        abstract!
        sealed!

        sig { returns(T::Boolean) }
        def up_to_date? = blobs.all?(&:up_to_date?)

        # The positional data that the user submitted for creation.
        sig { abstract.returns(Positions) }
        def position; end

        sig { abstract.returns(T::Array[Blob]) }
        def blobs; end

        sig { abstract.params(blobs: T::Array[Blob]).returns(Results) }
        def to_result(blobs); end

        class File < T::Struct
          include Requests
          include GitHub::Memoizer

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :position, Positions::File

          sig { override.returns(T::Array[Blob]) }
          def blobs = [blob]

          sig { returns(Blob) }
          memoize def blob
            Blob.new(
              state: Blob::State::Current,
              commit_oid: position.commit_oid,
              path: position.path,
              source_base_commit_oid: position.base_commit_oid,
              source_head_commit_oid: position.head_commit_oid,
              target_base_commit_oid: base_commit_oid,
              target_head_commit_oid: head_commit_oid,
            )
          end

          sig { override.params(blobs: T::Array[Blob]).returns(Results::File) }
          def to_result(blobs)
            blob = T.must(blobs.first)

            Results::File.new(
              base_commit_oid:,
              head_commit_oid:,
              commit_oid: blob.commit_oid,
              path: blob.path,
              state: blob.state,
            )
          end
        end

        class Line < T::Struct
          include Requests
          include GitHub::Memoizer

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :position, Positions::Line

          sig { override.returns(T::Array[Blob]) }
          def blobs = [blob]

          sig { returns(Blob) }
          memoize def blob
            Blob.new(
              state: Blob::State::Current,
              commit_oid: position.commit_oid,
              path: position.path,
              line: position.line,
              source_base_commit_oid: position.base_commit_oid,
              source_head_commit_oid: position.head_commit_oid,
              target_base_commit_oid: base_commit_oid,
              target_head_commit_oid: head_commit_oid,
            )
          end

          sig { override.params(blobs: T::Array[Blob]).returns(Results::Line) }
          def to_result(blobs)
            blob = T.must(blobs.first)

            Results::Line.new(
              base_commit_oid:,
              head_commit_oid:,
              commit_oid: blob.commit_oid,
              path: blob.path,
              line: blob.line,
              state: blob.state,
            )
          end
        end

        class Multiline < T::Struct
          include Requests
          include GitHub::Memoizer

          const :base_commit_oid, String
          const :head_commit_oid, String
          const :position, Positions::Multiline

          sig { override.returns(T::Array[Blob]) }
          def blobs = [start_blob, end_blob]

          sig { returns(Blob) }
          memoize def start_blob
            Blob.new(
              state: Blob::State::Current,
              commit_oid: position.start_commit_oid,
              path: position.start_path,
              line: position.start_line,
              source_base_commit_oid: position.base_commit_oid,
              source_head_commit_oid: position.head_commit_oid,
              target_base_commit_oid: base_commit_oid,
              target_head_commit_oid: head_commit_oid,
            )
          end

          sig { returns(Blob) }
          memoize def end_blob
            Blob.new(
              state: Blob::State::Current,
              commit_oid: position.end_commit_oid,
              path: position.end_path,
              line: position.end_line,
              source_base_commit_oid: position.base_commit_oid,
              source_head_commit_oid: position.head_commit_oid,
              target_base_commit_oid: base_commit_oid,
              target_head_commit_oid: head_commit_oid,
            )
          end

          sig { override.params(blobs: T::Array[Blob]).returns(Results::Multiline) }
          def to_result(blobs)
            start_blob = T.must(blobs.first)
            end_blob = T.cast(blobs.second, Blob)

            Results::Multiline.new(
              base_commit_oid:,
              head_commit_oid:,
              end_commit_oid: end_blob.commit_oid,
              end_path: end_blob.path,
              end_line: end_blob.line,
              end_state: end_blob.state,
              start_commit_oid: start_blob.commit_oid,
              start_path: start_blob.path,
              start_line: start_blob.line,
              start_state: start_blob.state,
            )
          end
        end
      end
    end
  end
end
