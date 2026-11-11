# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        class File < T::Struct
          const :path, String
          const :commit_oid, String
          const :commit_range, Types::CommitRange
          const :context, Locations::Context, factory: -> { Locations::Context.unresolved }

          sig { params(context: Locations::Context).returns(Locations::File) }
          def with_context(context) = Locations::File.new(path:, commit_oid:, commit_range:, context:)

          sig { returns(String) }
          def base_commit_oid = commit_range[0]

          sig { returns(String) }
          def head_commit_oid = commit_range[1]

          sig { returns(T::Boolean) }
          def targeting_base? = commit_oid == base_commit_oid

          sig { returns(Positions::File) }
          def to_positioning
            Positions::File.new(path:, commit_oid:, base_commit_oid:, head_commit_oid:)
          end

          sig { returns(T.nilable(Integer)) }
          def line = nil

          sig { params(other: T.untyped).returns(T::Boolean) }
          def ==(other)
            return false unless other.is_a?(File)

            path == other.path &&
              commit_oid == other.commit_oid &&
              commit_range == other.commit_range
          end
        end
      end
    end
  end
end
