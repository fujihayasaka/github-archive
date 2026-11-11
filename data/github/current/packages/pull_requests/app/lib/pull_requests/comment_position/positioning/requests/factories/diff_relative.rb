# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        module Factories
          # Factory for building requests from Inputs::DiffRelative from API requests, now deprecated.
          #
          # == Purpose
          #
          # DiffRelative is a legacy input format from the original PR review API.
          # New code should prefer Blobs or Positioning inputs with explicit line numbers.
          #
          # == Input Format
          #
          # - **path**: File path in the repository
          # - **position**: 1-based offset into the diff text (counting from first line after header)
          # - **base_commit_oid / head_commit_oid**: The diff range the position was computed against
          #
          # == Position Semantics
          #
          # A diff position is NOT a line number - it's an index into the unified diff.
          # For example, position 5 means "the 5th line of the diff output", which could
          # be a context line, addition, or deletion.
          #
          # == Resolution
          #
          # The Position location type requires diff resolution to convert to actual
          # line numbers. The diff resolver will:
          # 1. Load the diff for the commit range
          # 2. Find the line at the given position
          # 3. Extract base_line and head_line from that diff line
          #
          # Always produces a Line request. After resolution, the Position becomes a
          # Line location with concrete line numbers.
          #
          # Used by Processor when handling Inputs::DiffRelative.
          class DiffRelative
            # Builds a Line request from a diff-relative position input.
            sig { params(input: Positioner::Inputs::DiffRelative, target_range: Types::CommitRange).returns(Requests::Line) }
            def self.build(input:, target_range:)
              source_range = T.let([input.base_commit_oid, input.head_commit_oid], Types::CommitRange)

              Requests::Line.new(
                input:,
                target_range:,
                state: Locations::State.new(
                  source_range:,
                  target_range:,
                  input: Locations::Position.new(
                    path: input.path,
                    position: input.position,
                    commit_range: source_range,
                  ),
                ),
              )
            end
          end
        end
      end
    end
  end
end
