# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Inputs
        # API input values for positioning comments using legacy diff-relative positioning
        # with integer offset from the top of the diff hunk in the commit range between base and head commits.
        class DiffRelative < T::Struct
          const :identifier, String, factory: -> { SecureRandom.hex(8) }
          const :base_commit_oid, String
          const :head_commit_oid, String
          const :path, String
          const :position, Integer

          # Parse and validate diff-relative positioning parameters, returning either a valid DiffRelative instance or an error.
          sig do
            params(
              base_commit_oid: T.nilable(String),
              head_commit_oid: T.nilable(String),
              path: T.nilable(String),
              position: T.nilable(Integer)
            ).returns(T.any(DiffRelative, CommentPosition::Errors))
          end
          def self.parse(base_commit_oid:, head_commit_oid:, path:, position:)
            if base_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(base_commit_oid)
              CommentPosition::Errors::Parameter.new(base_commit_oid:)
            elsif head_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(head_commit_oid)
              CommentPosition::Errors::Parameter.new(head_commit_oid:)
            elsif path.nil? || path.blank?
              CommentPosition::Errors::Parameter.new(path:)
            elsif position.nil?
              CommentPosition::Errors::Parameter.new(position:)
            else
              new(base_commit_oid:, head_commit_oid:, path:, position:)
            end
          end
        end
      end
    end
  end
end
