# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    # Translates comment positions in a PR diff from one version of the diff to another.
    #
    # == Overview
    #
    # When a pull request's head commit changes, existing review comments need their
    # positions recalculated to point to the equivalent location in the new diff. This
    # module handles that translation, accepting positions in various input formats and
    # producing results that can represent the new position as absolute blob coordinates
    # or relative diff offsets.
    #
    # This package operates indepednently of Pull Requests and operates purely off of git
    # commits and paths.
    #
    # == Input Types
    #
    # Positions can arrive in several formats:
    #
    # * `Inputs::Blobs` — Absolute positions within a blob.
    # * `Inputs::DiffRelative` — Legacy diff-relative offsets: an integer representing the
    #    line's index-offset position of `git diff` lines.
    # * `Inputs::ThreadColumns` — Database state of an existing PullRequestReviewThread.
    # * `Inputs::Positioning` — Modern positioning schema: Positions::Line, Positions::File,
    #    or Positions::Multiline.
    #
    # == Output Types
    #
    # Results represent the resolved position in the target diff:
    #
    # * `Results::Line` — Single-line comment with resolved coordinates.
    # * `Results::Multiline` — Multi-line comment spanning a range of lines.
    # * `Results::File` — File-level comment with no specific line.
    # * `Results::Invalid` — Resolution failed; includes an error reason.
    #
    # == Processing Flow
    #
    # 1. Inputs are normalized into concrete location types: file, line (two for
    #    multiline comments), or diff-position.
    # 2. Diff-positions are resolved to line numbers, or transitioned to invalid.
    # 3. Diff context is loaded at the source commit range for original position data.
    # 4. Positions are retargeted from source to target commit range.
    # 5. Diff context is loaded at the target range for final position metadata.
    # 6. Positions outside the diff are validated against blob data.
    #
    # == External Services
    #
    # * **GitRPC** — Used for diff parsing and blob validation. Loads GitHub::Diff
    #   objects and validates that paths/lines exist at specific commits.
    # * **SpokesAPI** — GetDiffPositions RPC for retargeting positions across commit
    #   ranges. Maps line numbers through commit history when the PR head moves.
    #
    # == Key Components
    #
    # * `Service` — Entry point; returns Hash[Input => Result].
    # * `Command` — I/O adapter wrapping GitRPC and SpokesAPI calls.
    # * `Processor` — Orchestrates the processing pipeline.
    # * `Requests` — Normalized position requests.
    # * `Locations` — Coordinates within a commit range with resolved diff metadata.
    # * `Results` — Final output with resolved positions.
    #
    module Positioning
    end
  end
end
