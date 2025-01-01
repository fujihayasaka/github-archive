# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Legacy
      module Positioner
        class Reader
          include IReader
          include GitHub::Memoizer

          sig { params(repository: Repository).void }
          def initialize(repository:)
            @repository = repository
            @diffs = T.let({}, T::Hash[Positions::DiffRange, GitHub::Diff])
          end

          sig do
            override.params(
              range: Positions::DiffRange,
              paths: T::Array[String]
            ).void
          end
          def add_paths(range:, paths:)
            diff = begin
              @diffs[range] ||= GitHub::Diff.new(@repository, range.start_commit_oid, range.end_commit_oid)
            end

            paths.each { diff.add_path(_1) }
          end

          sig do
            override.params(
              range: Positions::DiffRange,
              path: String,
              position: Integer,
            ).returns(T.nilable(String))
          end
          def diff_hunk_for(range:, path:, position:)
            return unless diff = @diffs[range]
            return unless entry = T.let(diff[path], T.nilable(GitHub::Diff::Entry))

            # Borrowed from: PullRequestReviewComment::AbstractPositionData
            excerpt = []
            diff_lines = entry.lines

            position.downto(0).each do |index|
              line = diff_lines[index]
              excerpt.unshift(line)
              break if line[0] == "@"
            end

            excerpt.join("\n")
          end

          sig do
            override.params(
              range: Positions::DiffRange,
              path: String,
            ).returns(T.nilable(String))
          end
          def right_path_for(range:, path:)
            @diffs[range]&.delta_for_path(path)&.paths&.compact&.last
          end

          sig do
            override.params(
              range: Positions::DiffRange,
              path: String,
              line: Integer,
              left_blob: T::Boolean,
            ).returns(T.nilable(Integer))
          end
          def position_for(range:, path:, line:, left_blob:)
            @diffs[range]&.position_for(line, path, left_blob)
          end

          sig { override.void }
          def call
            @diffs.values.each do |diff|
              diff.maximize_single_entry_limits!
              diff.load_diff
            end
          end
        end
      end
    end
  end
end
