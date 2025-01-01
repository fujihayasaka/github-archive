# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Inputs
        # API inputs of Positions.
        class Positioning < T::Struct
          const :identifier, T.any(String, Integer), factory: -> { SecureRandom.hex(8) }
          const :positioning, Positions

          # Parse and validate positioning parameters, returning either a valid Positioning instance or an error.
          sig do
            params(
              base_commit_oid: T.nilable(String),
              head_commit_oid: T.nilable(String),
              positioning: T.untyped
            ).returns(T.any(Positioning, CommentPosition::Errors))
          end
          def self.parse(base_commit_oid:, head_commit_oid:, positioning:)
            if base_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(base_commit_oid)
              CommentPosition::Errors::Parameter.new(base_commit_oid:)
            elsif head_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(head_commit_oid)
              CommentPosition::Errors::Parameter.new(head_commit_oid:)
            else
              case positioning = Positions::Parser.parse(positioning, base_commit_oid:, head_commit_oid:)
              when CommentPosition::Errors
                positioning
              else
                new(positioning:)
              end
            end
          end
        end
      end
    end
  end
end
