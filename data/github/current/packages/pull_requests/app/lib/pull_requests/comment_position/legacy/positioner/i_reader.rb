# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        module IReader
          extend T::Helpers
          interface!

          sig do
            abstract.params(
              range: Positions::DiffRange,
              paths: T::Array[String]
            ).void
          end
          def add_paths(range:, paths:); end

          sig do
            abstract.params(
              range: Positions::DiffRange,
              path: String,
              line: Integer,
              left_blob: T::Boolean,
            ).returns(T.nilable(Integer))
          end
          def position_for(range:, path:, line:, left_blob:); end

          sig do
            abstract.params(
              range: Positions::DiffRange,
              path: String,
            ).returns(T.nilable(String))
          end
          def right_path_for(range:, path:); end

          sig do
            abstract.params(
              range: Positions::DiffRange,
              path: String,
              position: Integer,
            ).returns(T.nilable(String))
          end
          def diff_hunk_for(range:, path:, position:); end

          sig { abstract.void }
          def call; end
        end
      end
    end
  end
end
