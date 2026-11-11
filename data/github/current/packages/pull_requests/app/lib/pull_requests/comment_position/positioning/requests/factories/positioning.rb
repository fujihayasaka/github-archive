# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        module Factories
          # Factory for building requests from Inputs::Positioning from API requests.
          #
          # == Purpose
          #
          # Positioning input wraps a Positions struct (Line, Multiline, File, Indeterminate, Errored).
          # The Positions struct is the canonical representation of a comment's position,
          # containing all necessary data for resolution.
          #
          # == Request Type Determination
          #
          # Maps directly from Positions type:
          # - Positions::Line → Requests::Line
          # - Positions::Multiline → Requests::Multiline
          # - Positions::File → Requests::File
          # - Positions::Indeterminate/Errored → Requests::Invalid
          #
          # == Source Range Optimization
          #
          # A key optimization: if the positioning's commit already matches the target
          # range on the relevant side, we skip repositioning entirely.
          #
          # For example, a left-side (base) comment where positioning.base_commit_oid
          # equals target_range[0] doesn't need repositioning - the line numbers are
          # already correct for the target.
          #
          # This is handled by derive_source_range which returns target_range when
          # commits match, avoiding unnecessary git-blame operations.
          #
          # Used by Processor when handling Inputs::Positioning.
          class Positioning
            RequestTypes = T.type_alias { T.any(Requests::Line, Requests::Multiline, Requests::File, Requests::Invalid) }

            # Builds a request from a Positions struct by mapping the struct type to the
            # corresponding request type.
            sig { params(input: T.any(Positioner::Inputs::Positioning, Positioner::Inputs::ThreadColumns), target_range: Types::CommitRange, positioning: T.nilable(Positions), needs_diff_hunk: T::Boolean).returns(RequestTypes) }
            def self.build(input:, target_range:, positioning: nil, needs_diff_hunk: true)
              if input.is_a?(Positioner::Inputs::Positioning)
                positioning = input.positioning
              end

              if positioning.nil?
                return Requests::Invalid.new(input:, target_range:, error: CommentPosition::Errors::MissingPositioning.new)
              end

              positioning_range = T.let([positioning.base_commit_oid, positioning.head_commit_oid], Types::CommitRange)

              # Determine the appropriate source_range based on whether the positioning's commit
              # matches the target range. This avoids unnecessary repositioning when the line's
              # side hasn't changed (e.g., left-side lines when bases match).
              source_range = derive_source_range(positioning, target_range)

              case positioning
              when Positions::Line
                Requests::Line.new(
                  input:,
                  target_range:,
                  needs_diff_hunk:,
                  state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::Line.new(
                      path: positioning.path,
                      commit_oid: positioning.commit_oid,
                      commit_range: source_range,
                      line: positioning.line,
                    ),
                  )
                )
              when Positions::Multiline
                Requests::Multiline.new(
                  input:,
                  target_range:,
                  needs_diff_hunk:,
                  end_state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::Line.new(
                      path: positioning.end_path,
                      commit_oid: positioning.end_commit_oid,
                      commit_range: source_range,
                      line: positioning.end_line,
                    ),
                  ),
                  start_state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::Line.new(
                      path: positioning.start_path,
                      commit_oid: positioning.start_commit_oid,
                      commit_range: source_range,
                      line: positioning.start_line,
                    ),
                  )
                )
              when Positions::File
                Requests::File.new(
                  input:,
                  target_range:,
                  needs_diff_hunk:,
                  state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::File.new(
                      path: positioning.path,
                      commit_oid: positioning.commit_oid,
                      commit_range: source_range,
                    ),
                  )
                )
              when Positions::Indeterminate, Positions::Errored
                Requests::Invalid.new(input:, target_range:, error: CommentPosition::Errors::Unknown.new)
              else
                T.absurd(positioning)
              end
            end

            # Determines the source_range to use for a positioning.
            #
            # This is an optimization to avoid unnecessary repositioning. When the
            # positioning's commit matches the target on the relevant side, we return
            # target_range directly. This tells the processor "no repositioning needed"
            # because source_range == target_range.
            #
            # == Left-side (base) comments
            # If commit_oid == base_commit_oid AND base matches target_base, skip reposition.
            #
            # == Right-side (head) comments
            # If commit_oid == head_commit_oid AND head matches target_head, skip reposition.
            #
            # == Otherwise
            # Use the positioning's original range; repositioning will map to target.
            sig { params(positioning: Positions, target_range: Types::CommitRange).returns(Types::CommitRange) }
            private_class_method def self.derive_source_range(positioning, target_range)
              target_base_oid, target_head_oid = target_range

              case positioning
              when Positions::Line, Positions::File
                if positioning.commit_oid == positioning.base_commit_oid && positioning.base_commit_oid == target_base_oid
                  # Left-side line with matching base - no repositioning needed
                  target_range
                elsif positioning.commit_oid == positioning.head_commit_oid && positioning.head_commit_oid == target_head_oid
                  # Right-side line with matching head - no repositioning needed
                  target_range
                else
                  [positioning.base_commit_oid, positioning.head_commit_oid]
                end
              else
                [positioning.base_commit_oid, positioning.head_commit_oid]
              end
            end
          end
        end
      end
    end
  end
end
