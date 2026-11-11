# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        class Position < T::Struct
          const :path, String
          const :commit_range, Types::CommitRange
          const :position, Integer
          const :context, Locations::Context, factory: -> { Locations::Context.unresolved }

          sig { params(context: Locations::Context).returns(Locations::Position) }
          def with_context(context) = Locations::Position.new(path:, commit_range:, position:, context:)

          sig { params(other: T.untyped).returns(T::Boolean) }
          def ==(other)
            return false unless other.is_a?(Position)

            path == other.path &&
              commit_range == other.commit_range &&
              position == other.position
          end
        end
      end
    end
  end
end
