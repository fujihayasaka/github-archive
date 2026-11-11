# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      # Type aliases specific to the Positioning module.
      #
      # == Location Type Progression
      #
      # Locations flow through stages with decreasing type possibilities:
      #
      # 1. **UnresolvedLocation** (Stage 0): Input from factories. Includes Position
      #    which is a legacy diff-relative format that must be converted.
      #
      # 2. **ResolvedLocation** (Stage 1+): After normalization. Position has been
      #    eliminated - all locations are now File, Line, or Invalid.
      #
      # This progression is enforced by Sorbet types, ensuring Position locations
      # cannot leak past the resolution stage.
      #
      # == Commit Ranges
      #
      # CommitRange is a [base_oid, head_oid] tuple representing a diff range.
      # - **source_range**: Where the comment currently lives
      # - **target_range**: Where we want to reposition it to
      #
      # When source_range == target_range, no repositioning is needed.
      module Types
        # Commit range tuple [base_commit_oid, head_commit_oid].
        # Represents the two commits that define a diff. The base is the "before"
        # state (left side, deletions) and head is "after" (right side, additions).
        CommitRange = T.type_alias { [String, String] }

        # Input locations before resolution. Position is only valid at this phase.
        # Position is a legacy diff-relative format (1-based offset into diff text)
        # that must be resolved to Line via diff lookup before further processing.
        UnresolvedLocation = T.type_alias { T.any(Locations::File, Locations::Line, Locations::Position, Locations::Invalid) }

        # Resolved locations after normalization. Position has been eliminated.
        # At this point, all locations are concrete (File/Line) or failed (Invalid).
        # This type is used throughout the rest of the pipeline.
        ResolvedLocation = T.type_alias { T.any(Locations::File, Locations::Line, Locations::Invalid) }

        # Request types produced by factories. Each maps to a specific result type.
        # Invalid requests pass through without processing.
        Request = T.type_alias { T.any(Requests::File, Requests::Line, Requests::Multiline, Requests::Invalid) }

        # Final result types from the positioning service.
        # Contains all positioning data and can be converted to:
        # - Positions struct (for storage)
        # - Positioner::Result (for legacy API compatibility)
        Result = T.type_alias { T.any(Results::File, Results::Line, Results::Multiline, Results::Invalid) }
      end
    end
  end
end
