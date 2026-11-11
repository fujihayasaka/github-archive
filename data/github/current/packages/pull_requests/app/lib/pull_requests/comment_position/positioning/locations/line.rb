# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        class Line < T::Struct
          const :path, String
          const :commit_oid, String
          const :commit_range, Types::CommitRange
          const :line, Integer
          const :context, Locations::Context, factory: -> { Locations::Context.unresolved }

          sig { params(context: Locations::Context).returns(Locations::Line) }
          def with_context(context) = Locations::Line.new(path:, commit_oid:, commit_range:, line:, context:)

          sig { returns(String) }
          def base_commit_oid = commit_range[0]

          sig { returns(String) }
          def head_commit_oid = commit_range[1]

          sig { returns(T::Boolean) }
          def targeting_base? = commit_oid == base_commit_oid

          sig { returns(Positions::Line) }
          def to_positioning
            Positions::Line.new(
              path:,
              commit_oid:,
              line:,
              base_commit_oid:,
              head_commit_oid:,
            )
          end

          sig { params(other: T.untyped).returns(T::Boolean) }
          def ==(other)
            return false unless other.is_a?(Line)

            path == other.path &&
              commit_oid == other.commit_oid &&
              commit_range == other.commit_range &&
              line == other.line
          end
        end
      end
    end
  end
end
