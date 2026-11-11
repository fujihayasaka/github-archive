# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        module Factories
          # Factory for building requests from Inputs::Blobs from API requests.
          #
          # == Purpose
          #
          # Blobs input provides explicit blob references for new comment creation.
          # This is the most direct input format - no legacy column fallbacks needed.
          #
          # == Input Format
          #
          # - **base_commit_oid / head_commit_oid**: The diff range
          # - **path**: File path in the repository
          # - **end_line / end_commit_oid**: The anchor line (required for line comments)
          # - **start_line / start_commit_oid**: The start of multiline range (optional)
          #
          # == Request Type Determination
          #
          # The factory determines request type based on which fields are present:
          # 1. **start_line present**: Multiline (both start and end specified)
          # 2. **end_line present, no start_line**: Line (single line comment)
          # 3. **no end_line**: File (file-level comment)
          #
          # Used by Processor when handling Inputs::Blobs.
          class Blobs
            RequestTypes = T.type_alias { T.any(Requests::Line, Requests::Multiline, Requests::File) }

            # Builds a request from Blobs input by examining which line fields are present.
            sig { params(input: Positioner::Inputs::Blobs, target_range: Types::CommitRange).returns(RequestTypes) }
            def self.build(input:, target_range:)
              source_range = commit_range = [input.base_commit_oid, input.head_commit_oid]

              location = if (end_line = input.end_line)
                Locations::Line.new(
                  commit_range:,
                  path: input.path,
                  line: end_line,
                  commit_oid: input.end_commit_oid
                )
              else
                Locations::File.new(
                  commit_range:,
                  commit_oid: input.end_commit_oid,
                  path: input.path,
                )
              end

              end_state = state = Locations::State.new(
                source_range:, target_range:,
                input: location,
              )

              case location
              when Locations::Line
                if (start_line = input.start_line)
                  Requests::Multiline.new(
                    input:, target_range:, end_state:,
                    needs_diff_hunk: true,
                    start_state: Locations::State.new(
                      source_range:,
                      target_range:,
                      input: Locations::Line.new(
                        commit_range:,
                        path: input.path,
                        commit_oid: input.start_commit_oid,
                        line: start_line,
                      )
                    )
                  )
                else
                  Requests::Line.new(input:, target_range:, state:, needs_diff_hunk: true)
                end
              when Locations::File
                Requests::File.new(input:, target_range:, state:, needs_diff_hunk: true)
              end
            end
          end
        end
      end
    end
  end
end
