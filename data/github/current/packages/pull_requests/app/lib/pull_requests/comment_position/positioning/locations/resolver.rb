# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Locations
        # Resolver applies available transformations to derive a target location.
        #
        # This class centralizes all location derivation logic. It operates as a
        # transformation pipeline:
        # - Apply reposition transformation (if reposition_result present)
        # - Apply diff resolution (if diff_result present)
        # - Apply blob validation (if blob_result present)
        # - Return the best location computable from available data
        #
        # The caller passes whatever results are available, and gets back the
        # location that can be derived from that data. There are no "modes" —
        # just a linear pipeline with early returns when data is missing or invalid.
        #
        # == Design Rationale
        #
        # The pipeline order reflects data dependencies:
        #
        # 1. **Reposition first**: When moving comments between commit ranges (e.g., from
        #    an old PR head to a new one), reposition remaps line numbers using git-blame.
        #    This must happen before diff resolution because we need the NEW coordinates
        #    to look up in the NEW diff.
        #
        # 2. **Diff resolution second**: Once we have coordinates in the target range,
        #    we check if the line exists in the diff. This tells us if the comment
        #    is on changed code, context lines, or outside the diff entirely.
        #
        # 3. **Blob validation last**: For lines outside the diff, we validate against
        #    the blob to ensure the line number is within file bounds. This is a fallback
        #    that only runs when diff resolution can't determine validity.
        #
        # == Input Types
        #
        # - **Line**: A line number + path + commit. Most common case.
        # - **File**: A path + commit without a specific line. Used for file-level comments.
        # - **Position**: A legacy diff position (1-based offset into diff text). Must be
        #   converted to Line via diff resolution. Cannot use reposition.
        # - **Invalid**: Pass-through. Already failed in a previous step.
        #
        # Returns a resolved location (Line, File, or Invalid) with attached Context
        # containing metadata about how the resolution occurred.
        #
        # Called by Locations::State during location resolution.
        class Resolver
          include GitHub::Memoizer

          sig do
            params(
              location: Types::UnresolvedLocation,
              target_range: Types::CommitRange,
              reposition_result: T.nilable(Loaders::Results::Reposition),
              diff_result: T.nilable(Loaders::Results::Diff),
              blob_result: T.nilable(Loaders::Results::Blob),
            ).void
          end
          def initialize(location:, target_range:, reposition_result:, diff_result:, blob_result:)
            @location = location
            @target_range = target_range
            @reposition_result = reposition_result
            @diff_result = diff_result
            @blob_result = blob_result
          end

          # Main resolution entry point. Transforms the input location through available
          # results to produce a resolved location with full context.
          #
          # The method is structured as a series of guards (early returns) followed by
          # transformations. Guards are ordered by dependency - we can't attempt later
          # operations if earlier ones failed.
          sig { returns(Types::ResolvedLocation) }
          def to_location
            # Invalid locations are terminal - they've already failed upstream and carry
            # their failure context. No further processing is possible or meaningful.
            return @location if @location.is_a?(Invalid)

            # Position is fundamentally different from Line/File. A Position is an index
            # into the diff text itself, not a line number in a file. It can ONLY be
            # resolved by finding that position in the diff - reposition doesn't apply
            # (you can't git-blame a diff offset) and blob validation is irrelevant.
            # We handle it in a completely separate code path.
            if @location.is_a?(Position)
              if !@diff_result&.resolved?
                return invalid_for_position
              else
                return resolve_position
              end
            end

            # From here on, we're dealing with Line or File locations.

            # Reposition failure means git-blame couldn't track the line to the target
            # commit range. This is terminal because we don't know where the line moved.
            # Common causes: line was deleted, file was deleted, no common ancestor.
            if @reposition_result&.failed?
              return invalid
            end

            # Working copy of the location that we'll transform through the pipeline.
            # We keep @location unchanged for type checking in resolve_line/resolve_file.
            location = @location

            # Apply reposition transformation: remap coordinates from original commit
            # range to target commit range. This updates the line number (for Line) and
            # potentially the path (if the file was renamed).
            if @reposition_result&.success?
              commit_oid = targeting_base? ? target_base_commit_oid : target_head_commit_oid
              path = @reposition_result.path || location.path

              case location
              when Line
                location = Line.new(path:, commit_oid:, commit_range: @target_range, line: @reposition_result.line || location.line)
              when File
                location = File.new(path:, commit_oid:, commit_range: @target_range)
              end
            end

            # Blob validation failure means the line number exceeds the file's line count.
            # This is terminal because we know the line doesn't exist in the file.
            return invalid if @blob_result&.invalid?

            # Diff resolution failure means the diff couldn't be loaded or parsed.
            # Different from "line not in diff" - this is an error condition.
            return invalid if @diff_result&.failed?

            # No diff result means we couldn't or didn't need to check the diff.
            # We still return a valid location, just with partial context.
            unless @diff_result
              case location
              when Line, File
                return location.with_context(context)
              else
                T.absurd(location)
              end
            end

            # Final transformation: apply diff resolution to determine exact position
            # in the diff, or mark as outside-diff if the line isn't in changed regions.
            case @location
            when Line
              resolve_line(location)
            when File
              resolve_file(location)
            else
              T.absurd(@location)
            end
          end

          private

          # Builds a unified Context from all available results.
          #
          # Context is memoized because it's accessed multiple times during resolution
          # (by resolve_line/resolve_file and by invalid) and the computation involves
          # conditional logic we don't want to repeat.
          #
          # == Priority Cascade
          #
          # The order of checks reflects data quality: more specific/reliable sources
          # are preferred over less specific ones.
          #
          # 1. **Diff resolved**: We found the exact line in the diff. This gives us
          #    the most complete information - position, hunk, line type, both sides.
          #
          # 2. **Diff closest match**: The exact line wasn't in the diff, but we found
          #    a nearby line. Useful for "snap to nearest" behavior.
          #
          # 3. **Diff failed**: The diff couldn't be loaded/parsed. Propagate the error.
          #
          # 4. **Reposition failed**: Git-blame couldn't track the line. Propagate error.
          #
          # 5. **Blob invalid**: Line number exceeds file bounds. Propagate error.
          #
          # 6. **Fallback**: Build partial context from whatever we have. This handles
          #    lines outside the diff (valid but not in changed regions) and cases
          #    where no diff was requested.
          sig { returns(Context) }
          memoize def context
            # Best case: diff found the exact line. We have complete positioning data.
            if @diff_result&.resolved?
              Context.new(
                match_type: @diff_result.match_type,
                outcome: @diff_result.outcome,
                position: @diff_result.position,
                base_line: @diff_result.base_line,
                base_path: @diff_result.base_path,
                head_line: @diff_result.head_line,
                head_path: @diff_result.head_path,
                hunk: @diff_result.hunk,
                line_type: @diff_result.line_type || Enums::LineType::Context,
              )
            elsif @diff_result&.closest_match?
              # Line wasn't in diff but we found a nearby anchor point.
              # Outcome is Unknown because the caller must decide what to do.
              Context.new(
                match_type: Enums::MatchType::Closest,
                outcome: Enums::Outcome::Unknown,
                base_line: @diff_result.base_line,
                base_path: @diff_result.base_path,
                head_line: @diff_result.head_line,
                head_path: @diff_result.head_path,
                hunk: @diff_result.hunk,
              )
            elsif @diff_result&.failed?
              # Diff loading/parsing error. Preserve the specific failure reason.
              Context.failure(
                outcome: @diff_result.outcome,
                failed_from: :diff,
              )
            elsif @reposition_result&.failed?
              # Git-blame tracking failed. Preserve the specific failure reason.
              Context.failure(
                outcome: @reposition_result.to_outcome,
                failed_from: :reposition,
              )
            elsif @blob_result&.invalid?
              # Line number out of bounds. Preserve the specific failure reason.
              Context.failure(
                outcome: @blob_result.to_outcome,
                failed_from: :blob,
              )
            else
              # No failure, but line is either outside diff or no diff was checked.
              # Build the best context we can from available data.
              not_in_diff = !!@diff_result&.not_in_diff?

              # Pre-compute values derived from not_in_diff to avoid Sorbet flow analysis issues
              match_type = not_in_diff ? Enums::MatchType::NotInDiff : Enums::MatchType::NotResolved
              default_outcome = not_in_diff ? Enums::Outcome::OutsideDiff : Enums::Outcome::Unknown

              # Prefer repositioned path, fall back to original location path
              effective_path = @reposition_result&.success? ? @reposition_result.path : nil
              effective_path ||= @location.path

              # Prefer repositioned line, fall back to original location line
              effective_line = if @reposition_result&.success? && @location.is_a?(Line)
                @reposition_result.line
              elsif @location.is_a?(Line)
                @location.line
              end

              # For lines in unchanged regions (between hunks, before/after diff),
              # diff_resolver calculates equivalent line numbers on both sides.
              # These are more accurate than just using effective_line for both.
              diff_base_path = @diff_result&.base_path
              diff_head_path = @diff_result&.head_path
              diff_base_line = @diff_result&.base_line
              diff_head_line = @diff_result&.head_line

              # For paths NOT in the diff (only one side set), don't fall back to effective_path.
              # This allows handle_unchanged_files! to distinguish between:
              # - File in diff, line outside hunks (both paths set by diff resolver)
              # - File not in diff at all (only one path set)
              # For the latter case, blob validation is needed to verify the path exists.
              #
              # Preserve the diff result's outcome (e.g., ContentTooLarge) rather than
              # always using OutsideDiff, so result builders can detect specific conditions.
              diff_outcome = @diff_result&.outcome
              Context.new(
                match_type:,
                outcome: diff_outcome || default_outcome,
                base_path: diff_base_path || (not_in_diff ? nil : effective_path),
                base_line: diff_base_line || (not_in_diff ? nil : effective_line),
                head_path: diff_head_path || (not_in_diff ? nil : effective_path),
                head_line: diff_head_line || (not_in_diff ? nil : effective_line),
              )
            end
          end

          # Resolves a Line location using diff context.
          #
          # Two valid outcomes:
          # 1. **resolved**: Line found in diff. Use the context's base/head line numbers
          #    which may differ from input (e.g., file was renamed, line shifted).
          # 2. **outside_diff**: Line is valid but not in changed regions. Keep the
          #    target_location's coordinates (already transformed by reposition if applicable).
          #
          # We select base vs head coordinates based on which side the original comment
          # was on. A comment on the base side stays on the base side throughout its life.
          sig { params(target_location: Types::ResolvedLocation).returns(T.any(Line, Invalid)) }
          def resolve_line(target_location)
            return invalid unless @location.is_a?(Line)
            return invalid unless target_location.is_a?(Line)

            if context.resolved?
              # Diff found the line - use the diff's coordinates which account for
              # renames and line number changes between base and head.
              resolved_path = (targeting_base? ? context.base_path : context.head_path) || target_location.path
              resolved_line = (targeting_base? ? context.base_line : context.head_line) || target_location.line

              Line.new(
                path: resolved_path,
                line: resolved_line,
                commit_oid: target_location.commit_oid,
                commit_range: @target_range,
                context:,
              )
            elsif context.outside_diff?
              # Line is valid but in unchanged code. The target_location already has
              # the correct coordinates from reposition (or original if no reposition).
              Line.new(
                path: target_location.path,
                line: target_location.line,
                commit_oid: target_location.commit_oid,
                commit_range: @target_range,
                context:,
              )
            else
              invalid
            end
          end

          # Resolves a File location using diff context.
          #
          # Simpler than resolve_line because there's no line number to track.
          # The main value add is detecting renamed files via the diff's a_path/b_path.
          sig { params(target_location: Types::ResolvedLocation).returns(T.any(File, Invalid)) }
          def resolve_file(target_location)
            return invalid unless @location.is_a?(File)
            return invalid unless target_location.is_a?(File)

            if context.resolved?
              # Use diff's path which handles renames (a_path != b_path)
              resolved_path = (targeting_base? ? context.base_path : context.head_path) || target_location.path

              File.new(
                path: resolved_path,
                commit_oid: target_location.commit_oid,
                commit_range: @target_range,
                context:,
              )
            elsif context.outside_diff?
              # File exists but wasn't changed. Keep original path.
              File.new(
                path: target_location.path,
                commit_oid: target_location.commit_oid,
                commit_range: @target_range,
                context:,
              )
            else
              invalid
            end
          end

          # Converts a Position location to a Line location via diff resolution.
          #
          # Position is a legacy format - a 1-based offset into the diff text. To show
          # the comment on a specific line, we must resolve the position to find what
          # line number it corresponds to.
          #
          # Unlike Line/File, we derive the side (base vs head) from the diff result,
          # not from the input. A position on a deletion line maps to base; a position
          # on an addition or context line maps to head.
          sig { returns(T.any(Line, Invalid)) }
          def resolve_position
            return invalid unless @location.is_a?(Position)
            return invalid unless context.resolved?

            # Determine which side based on the diff line type at this position.
            # Deletions exist only on base (left), additions only on head (right).
            position_is_left = context.targeting_base? || false
            resolved_line = position_is_left ? context.base_line : context.head_line
            resolved_path = (position_is_left ? context.base_path : context.head_path) || @location.path
            resolved_commit_oid = position_is_left ? target_base_commit_oid : target_head_commit_oid

            if resolved_line
              # Successfully converted Position to Line with full context
              Line.new(
                line: resolved_line,
                path: resolved_path,
                commit_oid: resolved_commit_oid,
                commit_range: @target_range,
                context:,
              )
            else
              invalid_for_position
            end
          end

          # Creates an Invalid location preserving as much original data as possible.
          #
          # Used when resolution fails at any stage. The Invalid location carries:
          # - The failure reason (from context.outcome)
          # - Original path and line (for error reporting)
          # - The target commit range (for reference)
          # - Full context (for debugging)
          sig { returns(Invalid) }
          def invalid
            location = @location
            # Preserve original commit_oid where possible. For Position, we don't have
            # a single commit_oid (it's relative to a diff between two commits), so
            # we fall back to the head of the range.
            commit_oid = case location
            when Line, File, Invalid
              location.commit_oid
            when Position
              location.commit_range[1]
            else
              T.absurd(location)
            end

            Invalid.new(
              outcome: context.outcome,
              path: location.path,
              commit_oid:,
              commit_range: @target_range,
              line: location.is_a?(Line) ? location.line : nil,
              context:,
            )
          end

          # Invalid for Position locations - derives commit_oid from target range
          # Position is diff-relative and requires a valid diff result to resolve
          sig { returns(Invalid) }
          def invalid_for_position
            return invalid unless @location.is_a?(Position)

            Invalid.new(
              outcome: context.outcome,
              path: @location.path,
              commit_oid: target_head_commit_oid, # Default to head since we can't determine side without diff
              commit_range: @target_range,
              line: nil,
              context:,
            )
          end

          sig { returns(String) }
          def target_base_commit_oid = @target_range[0]

          sig { returns(String) }
          def target_head_commit_oid = @target_range[1]

          # A comment always stays on the same side over its life.
          # This checks if the original location targets the base (left) side.
          # Only valid for Line/File locations.
          sig { returns(T::Boolean) }
          def targeting_base?
            case @location
            when Line, File, Invalid
              @location.targeting_base?
            when Position
              # Position side is determined by the diff result, not input.
              # This method should not be called for Position.
              false
            else
              T.absurd(@location)
            end
          end
        end
      end
    end
  end
end
