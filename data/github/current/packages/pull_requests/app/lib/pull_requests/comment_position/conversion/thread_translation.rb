# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Conversion
      class ThreadTranslation
        sig { params(positioning: T.nilable(Positions)).void }
        def initialize(positioning:)
          @positioning = positioning
        end

        sig { returns(T.nilable(Symbol)) }
        def start_side
          case positioning = @positioning
          when PullRequests::CommentPosition::Positions::Multiline
            positioning.start_commit_oid == positioning.base_commit_oid ? :left : :right
          end
        end

        sig { returns(Promise[T.nilable(Symbol)]) }
        def async_start_side = Promise.resolve(start_side)

        # 1-index start line number.
        sig { returns(T.nilable(Integer)) }
        def start_line
          case positioning = @positioning
          when PullRequests::CommentPosition::Positions::Multiline
            positioning.start_line
          end
        end

        # 1-index start line number.
        sig { returns(Promise[T.nilable(Integer)]) }
        def async_start_line = Promise.resolve(start_line)

        # 0-index start line number.
        sig { returns(T.nilable(Integer)) }
        def start_line_zero_indexed
          start_line&.pred
        end

        sig { returns(Promise[T.nilable(Integer)]) }
        def async_start_line_zero_indexed = Promise.resolve(start_line_zero_indexed)

        sig { returns(T.nilable(Integer)) }
        def line
          case positioning = @positioning
          when PullRequests::CommentPosition::Positions::Multiline
            positioning.end_line
          when PullRequests::CommentPosition::Positions::Line
            positioning.line
          end
        end

        sig { returns(Promise[T.nilable(Integer)]) }
        def async_line = Promise.resolve(line)
      end
    end
  end
end
