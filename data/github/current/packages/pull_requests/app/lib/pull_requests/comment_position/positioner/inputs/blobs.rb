# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Inputs
        # API input values for positioning comments using the blob positioning format.
        # This struct represents comment positioning requests that specify exact blob locations
        # with commit OIDs, file paths, and line numbers rather than diff-relative positions.
        class Blobs < T::Struct
          DEFAULT_SIDE = Enums::Side::Right

          const :identifier, String, factory: -> { SecureRandom.hex(8) }
          const :base_commit_oid, String
          const :head_commit_oid, String
          const :path, String
          const :line, T.nilable(Integer)
          const :side, Enums::Side
          const :start_line, T.nilable(Integer)
          const :start_side, Enums::Side, default: Enums::Side::Right

          sig { returns(String) }
          def start_commit_oid = start_side.left? ? base_commit_oid : head_commit_oid

          sig { returns(String) }
          def end_commit_oid = end_side.left? ? base_commit_oid : head_commit_oid

          sig { returns(T.nilable(Integer)) }
          def blob_position = line&.pred

          sig { returns(Enums::SubjectType) }
          def subject_type = line.nil? && start_line.nil? ? Enums::SubjectType::File : Enums::SubjectType::Line

          alias blob_commit_oid end_commit_oid
          alias blob_path path
          alias end_path path
          alias end_line line
          alias end_side side


          # Parse and validate blob positioning parameters, returning either a valid Blobs instance or an error.
          sig do
            params(
              base_commit_oid: T.nilable(String),
              head_commit_oid: T.nilable(String),
              path: T.nilable(String),
              line: T.nilable(Integer),
              side: T.nilable(T.any(String, Symbol, Enums::Side)),
              start_line: T.nilable(Integer),
              start_side: T.nilable(T.any(String, Symbol, Enums::Side))
            ).returns(T.any(Blobs, CommentPosition::Errors))
          end
          def self.parse(base_commit_oid:, head_commit_oid:, path:, line:, side:, start_line:, start_side:)
            if base_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(base_commit_oid)
              CommentPosition::Errors::Parameter.new(base_commit_oid:)
            elsif head_commit_oid.nil? || !GitRPC::Util.valid_full_oid?(head_commit_oid)
              CommentPosition::Errors::Parameter.new(head_commit_oid:)
            elsif path.nil? || path.blank?
              CommentPosition::Errors::Parameter.new(path:)
            else
              side = Enums::Side.deserialize_with_default(side, default: DEFAULT_SIDE)
              start_side = Enums::Side.deserialize_with_default(start_side, default: DEFAULT_SIDE)

              new(path:, line:, side:, start_line:, start_side:, base_commit_oid:, head_commit_oid:)
            end
          end
        end
      end
    end
  end
end
