# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Structures describing the Positional request data from various locations such as PullRequestReviewThread.
      module Requests
        extend T::Helpers

        interface!
        sealed!

        sig { abstract.returns(Integer) }
        def identifier; end

        # The positional data that the user submitted for creation.
        sig { abstract.returns(Positions) }
        def position; end

        # Union type versus sealed! as this automatically allows methods that are defined on each type to work without
        # declaring them as an interface.
        Union = T.type_alias { T.any(File, Line, Multiline) }

        class File < T::Struct
          include Requests
          include GitHub::Memoizer

          const :identifier, Integer
          const :destination_range, Positions::DiffRange
          const :position, Positions::File

          sig { returns(Blob) }
          memoize def blob
            Blob.new(
              commit_oid: position.commit_oid,
              path: position.path,
              source_range: position.range,
              destination_range:,
            )
          end
        end

        class Line < T::Struct
          include Requests
          include GitHub::Memoizer

          const :identifier, Integer
          const :destination_range, Positions::DiffRange
          const :position, Positions::Line

          sig { returns(Blob) }
          memoize def blob
            Blob.new(
              commit_oid: position.commit_oid,
              path: position.path,
              line: position.line,
              source_range: position.range,
              destination_range:,
            )
          end
        end

        class Multiline < T::Struct
          include Requests
          include GitHub::Memoizer

          const :identifier, Integer
          const :destination_range, Positions::DiffRange
          const :position, Positions::Multiline

          sig { returns(Integer) }
          def start_line = position.start_line

          sig { returns(Integer) }
          def end_line = position.end_line

          sig { returns(Blob) }
          memoize def start_blob
            Blob.new(
              commit_oid: position.start_commit_oid,
              path: position.start_path,
              line: position.start_line,
              source_range: position.range,
              destination_range:,
            )
          end

          sig { returns(Blob) }
          memoize def end_blob
            Blob.new(
              commit_oid: position.end_commit_oid,
              path: position.end_path,
              line: position.end_line,
              source_range: position.range,
              destination_range:,
            )
          end
        end
      end
    end
  end
end
