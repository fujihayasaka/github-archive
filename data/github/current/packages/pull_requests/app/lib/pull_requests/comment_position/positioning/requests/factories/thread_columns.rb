# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Requests
        module Factories
          # Factory for building requests from existing PullRequestReviewThread database rows.
          #
          # == Purpose
          #
          # ThreadColumns is the most complex factory because it handles legacy data
          # from the database. Comment threads have multiple columns storing position
          # data in different formats, accumulated over years of product evolution.
          #
          # == Fallback Chain Priority
          #
          # The factory tries sources in order of reliability/recency:
          #
          # 1. **latest_positioning**: Most recent Positions struct. If it matches
          #    the target range exactly, we can use it directly (no repositioning).
          #
          # 2. **original_positioning**: The Positions struct from when the comment
          #    was created. Authoritative source for the original intent.
          #
          # 3. **original_* columns**: Legacy diff-relative columns (original_position,
          #    original_start_commit_id, original_end_commit_id). These predate the
          #    Positions struct but are still authoritative.
          #
          # 4. **blob_* columns**: Line numbers relative to a specific blob. More
          #    stable than diff positions across rebases.
          #
          # 5. **position column**: Current diff position. Last resort because it
          #    changes on every PR update.
          #
          # == Design Rationale
          #
          # - latest_positioning is checked first because if it matches target_range,
          #   we can skip ALL processing (no reposition, no diff lookup).
          # - original_positioning is next because it's the canonical source of truth.
          # - The legacy columns are fallbacks for old comments that predate Positions.
          # - Each fallback is progressively less reliable but covers more historical data.
          #
          # Used by Processor when handling Inputs::ThreadColumns.
          class ThreadColumns
            RequestTypes = T.type_alias { T.any(Requests::Line, Requests::Multiline, Requests::File, Requests::Invalid) }

            sig { params(input: Positioner::Inputs::ThreadColumns, target_range: Types::CommitRange).returns(RequestTypes) }
            def self.build(input:, target_range:)
              # Diff hunks are not needed for ThreadColumns inputs because we're
              # repositioning existing comments, not creating new ones. The UI
              # already has the diff context from the original comment.
              needs_diff_hunk = false

              # PRIORITY 1: latest_positioning that matches target range exactly.
              # This is the fast path - if the stored positioning is already for
              # the target commits, no repositioning needed at all.
              if latest_positioning = input.latest_positioning
                if valid_position?(latest_positioning) && positioning_matches_range?(latest_positioning, target_range)
                  return Positioning.build(
                    input:, target_range:, needs_diff_hunk:,
                    positioning: latest_positioning
                  )
                end
              end

              # PRIORITY 2: original_positioning is the authoritative source.
              # Even if it doesn't match target_range, it's the correct starting
              # point for repositioning.
              if original_positioning = input.original_positioning
                if valid_position?(original_positioning)
                  return Positioning.build(
                    input:, target_range:, needs_diff_hunk:,
                    positioning: original_positioning
                  )
                end
              end

              # PRIORITY 3: Use latest_positioning even if it doesn't match target range.
              # This handles cases where we have a valid positioning but need to reposition
              # it to the target range (e.g., multiline threads without legacy column data).
              if latest_positioning = input.latest_positioning
                if valid_position?(latest_positioning)
                  return Positioning.build(
                    input:, target_range:, needs_diff_hunk:,
                    positioning: latest_positioning)
                end
              end

              # From here on, we're handling legacy data without a Positions struct.
              # We need to construct Location objects from raw column values.

              commit_id = input.commit_id
              path = input.path

              return Requests::Invalid.new(input:, target_range:, error: CommentPosition::Errors::MissingPath.new) if path.nil? || path.blank?

              # SPECIAL CASE: File-level comments (subject_type = :file).
              # These don't have line numbers, so we bypass line resolution entirely.
              # We determine the side (left/right) from the left_blob flag.
              if input.subject_type.file? && path
                source_range = if (base_oid = input.original_start_commit_id) && (head_oid = input.original_end_commit_id)
                  [base_oid, head_oid]
                else
                  target_range
                end

                source_base_oid, source_head_oid = source_range
                commit_oid = input.left_blob ? source_base_oid : source_head_oid

                Requests::File.new(
                  input:, target_range:, needs_diff_hunk:,
                  state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::File.new(
                      path:,
                      commit_oid:,
                      commit_range: source_range
                    )
                  )
                )
              elsif (original_position = input.original_position) && (base_commit_oid = input.original_start_commit_id) && (head_commit_oid = input.original_end_commit_id)
                # PRIORITY 3: original_* columns - legacy diff-relative positioning.
                # These columns store the original diff position when the comment was
                # created. We create a Position location that will be resolved against
                # the original diff, then repositioned to target_range.
                commit_range = source_range = [base_commit_oid, head_commit_oid]

                if (start_position_offset = input.start_position_offset)
                  # Multiline: We store end position and an offset to derive start.
                  # start_position = original_position - start_position_offset
                  Requests::Multiline.new(
                    input:,
                    target_range:,
                    needs_diff_hunk:,
                    start_state: Locations::State.new(
                      source_range:,
                      target_range:,
                      input: Locations::Position.new(
                        path:,
                        commit_range:,
                        position: original_position - start_position_offset
                      )
                    ),
                    end_state: Locations::State.new(
                      source_range:,
                      target_range:,
                      input: Locations::Position.new(
                        path:,
                        commit_range:,
                        position: original_position
                      )
                    ),
                  )
                else
                  Requests::Line.new(
                    input:,
                    target_range:,
                    needs_diff_hunk:,
                    state: Locations::State.new(
                      source_range:,
                      target_range:,
                      input: Locations::Position.new(
                        path:,
                        commit_range:,
                        position: original_position
                      )
                    )
                  )
                end
              elsif (blob_position = input.blob_position) && (blob_path = input.blob_path)
                # PRIORITY 4: blob_* columns - line numbers in a specific blob.
                # More stable than diff positions because line numbers in a file
                # change less frequently than diff positions across rebases.
                source_range = commit_range = blob_source_range(input)

                source_base_oid, source_head_oid = source_range

                Requests::Line.new(
                  input:,
                  target_range:,
                  needs_diff_hunk:,
                  state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::Line.new(
                      path: blob_path,
                      commit_oid: input.left_blob ? source_base_oid : source_head_oid,
                      commit_range:,
                      line: blob_position.next, # blob_position is 0-indexed, we need 1-indexed
                    )
                  )
                )
              elsif (position = input.position) && (commit_oid = input.commit_id)
                # PRIORITY 5: current position column - last resort.
                # This is the current diff position which changes on every PR update.
                # It's the least reliable but covers edge cases where other columns
                # are missing.
                source_range = [
                  input.original_base_commit_id || input.pull_request_base_commit_oid,
                  commit_oid
                ]

                Requests::Line.new(
                  input:,
                  target_range:,
                  needs_diff_hunk:,
                  state: Locations::State.new(
                    source_range:,
                    target_range:,
                    input: Locations::Position.new(
                      path:,
                      commit_range: [input.pull_request_base_commit_oid, commit_oid], # TODO: We should migrate this to best_merge_base
                      position:,
                    )
                  )
                )
              else
                # No usable position data found - cannot process this comment.
                Requests::Invalid.new(input:, target_range:, error: CommentPosition::Errors::Unknown.new)
              end
            end

            # Checks if a Positions struct is a valid, processable type.
            # Indeterminate and Errored are not processable - they indicate
            # upstream failures in position computation.
            sig { params(positioning: Positions).returns(T::Boolean) }
            def self.valid_position?(positioning)
              case positioning
              when Positions::Line, Positions::File, Positions::Multiline
                true
              when Positions::Indeterminate, Positions::Errored
                false
              else
                T.absurd(positioning)
              end
            end

            # Constructs the source_range for blob_* column fallback.
            #
            # For left-side (base) blobs: [blob_commit, pr_head]
            # For right-side (head) blobs: [pr_base, blob_commit]
            #
            # This reconstructs the diff range that the blob_position was computed
            # against, falling back to PR commits when blob_commit_oid is missing.
            sig { params(input: Positioner::Inputs::ThreadColumns).returns(Types::CommitRange) }
            def self.blob_source_range(input)
              if input.left_blob
                [
                  input.blob_commit_oid || input.original_base_commit_id || input.pull_request_base_commit_oid,
                  input.pull_request_head_commit_oid
                ]
              else
                [
                  input.pull_request_base_commit_oid,
                  input.blob_commit_oid || input.pull_request_head_commit_oid
                ]
              end
            end

            sig { params(positioning: Positions, target_range: Types::CommitRange).returns(T::Boolean) }
            def self.positioning_matches_range?(positioning, target_range)
              target_base_oid, target_head_oid = target_range
              positioning.base_commit_oid == target_base_oid && positioning.head_commit_oid == target_head_oid
            end
          end
        end
      end
    end
  end
end
