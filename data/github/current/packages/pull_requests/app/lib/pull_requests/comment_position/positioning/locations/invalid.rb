# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        # Invalid location - context/retargeting failed
        class Invalid < T::Struct
          const :outcome, Enums::Outcome
          const :path, T.nilable(String), default: nil
          const :commit_oid, T.nilable(String), default: nil
          const :commit_range, T.nilable(Types::CommitRange), default: nil
          const :line, T.nilable(Integer), default: nil
          const :context, Locations::Context, factory: -> { Locations::Context.unresolved }

          sig { params(context: Locations::Context).returns(Locations::Invalid) }
          def with_context(context) = Locations::Invalid.new(outcome:, path:, commit_oid:, commit_range:, line:, context:)

          sig { returns(T.nilable(String)) }
          def base_commit_oid = commit_range&.at(0)

          sig { returns(T::Boolean) }
          def targeting_base?
            return false unless commit_range = self.commit_range

            commit_oid == commit_range[0]
          end

          sig { params(other: T.untyped).returns(T::Boolean) }
          def ==(other)
            return false unless other.is_a?(Invalid)

            outcome == other.outcome &&
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
