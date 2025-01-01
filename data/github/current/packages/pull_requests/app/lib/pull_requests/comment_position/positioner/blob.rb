# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      # Structure describing the location of a specific blob within git and the diff range used when generating it.
      class Blob < T::Struct
        const :path, String
        const :commit_oid, String
        const :line, T.nilable(Integer)
        const :source_range, Positions::DiffRange
        const :destination_range, Positions::DiffRange

        sig { params(other: T.untyped).returns(T::Boolean) }
        def ==(other)
          case other
          when Blob
            serialize.without("range", "destination_range") == other.serialize.without("range", "destination_range")
          else
            super
          end
        end

        sig { returns(T::Boolean) }
        def left?
          commit_oid == source_range.start_commit_oid
        end

        sig { returns(T::Boolean) }
        def up_to_date?
          if left?
            commit_oid == destination_range.start_commit_oid
          else
            commit_oid == destination_range.end_commit_oid
          end
        end

        sig { returns(String) }
        def target_commit_oid
          left? ? destination_range.start_commit_oid : destination_range.end_commit_oid
        end
      end
    end
  end
end
