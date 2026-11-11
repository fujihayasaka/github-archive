# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Enums
        # Re-export from Positioner for convenience. Side (Left/Right) indicates
        # which commit in a range a line belongs to.
        Side = Positioner::Enums::Side

        # Re-export from Positioner. SubjectType (Line/File) indicates whether
        # a comment is attached to a specific line or the file as a whole.
        SubjectType = Positioner::Enums::SubjectType

        # Describes how a location query matched against the diff.
        # Used by DiffResolver to communicate resolution outcomes.
        class MatchType < T::Enum
          enums do
            # Found the specific line in the diff
            Exact = new
            # Line not in diff, but found a nearby anchor for interpolation
            Closest = new
            # Line is valid but in unchanged code (between/before/after hunks)
            NotInDiff = new
            # Diff wasn't loaded or couldn't be processed
            NotResolved = new
          end
        end

        # Describes the type of diff line. Extracted from the diff hunk during resolution.
        # Defaults to Context for lines outside the diff (unchanged code).
        class LineType < T::Enum
          enums do
            # Line was added (+ prefix in diff, exists only on right/head)
            Addition = new
            # Line was deleted (- prefix in diff, exists only on left/base)
            Deletion = new
            # Unchanged context line (space prefix, exists on both sides)
            Context = new
          end
        end

        # Unified outcome enum for all positioning operations.
        #
        # Consolidates multiple legacy enums (FailureReason, State, IndeterminateReason)
        # into a single type that represents the complete outcome space. This makes
        # error handling consistent and enables precise error messages.
        #
        # The to_indeterminate_reason method maps these to legacy API symbols for
        # backwards compatibility with ThreadColumns and other external interfaces.
        class Outcome < T::Enum
          enums do
            # --- Success States ---
            # Valid at source range, no repositioning was needed
            Current = new
            # Successfully tracked to target range via git-blame
            Repositioned = new
            # Valid location but not in changed code (context lines, between hunks)
            OutsideDiff = new
            # Resolution not needed (e.g., Invalid input passthrough)
            NotApplicable = new

            # --- Path Failures ---
            # Path doesn't exist in the commit tree at all
            PathNotFound = new
            # Path existed in source but was deleted/renamed without match
            PathRemoved = new

            # --- Line Failures ---
            # Line was deleted or shifted beyond trackable range
            LineRemoved = new

            # --- Resource/System Failures ---
            # Blob or diff exceeds size limits, can't process
            ContentTooLarge = new
            # Diff resolution was skipped or not attempted
            DiffNotLoaded = new
            # Diff data is corrupt or unparseable
            DiffInvalid = new
            # Git backend error (timeout, unavailable, etc.)
            GitUnavailable = new

            # --- Catch-all ---
            # Input structure is invalid or unexpected
            MalformedInput = new
            # Fallback for unclassified errors
            Unknown = new
          end

          # Returns true if this outcome represents a successful resolution.
          # Success means we have a usable location, even if it required repositioning
          # or is outside the diff.
          sig { returns(T::Boolean) }
          def success?
            case self
            when Current, Repositioned, OutsideDiff, NotApplicable
              true
            else
              false
            end
          end

          sig { returns(T::Boolean) }
          def failure? = !success?

          # Maps to legacy indeterminate reason symbols for backwards compatibility.
          #
          # The ThreadColumns API and other external interfaces expect specific
          # symbol values. This method translates our precise outcomes into the
          # coarser legacy categories.
          sig { returns(Symbol) }
          def to_indeterminate_reason
            case self
            when LineRemoved
              :cannot_reposition_line
            when PathRemoved, PathNotFound, DiffNotLoaded
              :cannot_resolve_path
            when ContentTooLarge
              :blob_contents_too_large
            when MalformedInput
              :unexpected_blob_pattern
            else
              :unknown_error
            end
          end
        end
      end
    end
  end
end
