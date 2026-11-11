# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      module Loaders
        # DiffResolver handles diff loading and single-pass iteration for a specific commit range.
        # Returns Results::DiffResult objects containing raw match data - no Location/Context building.
        # Does NOT handle blob loading - that's a separate stage managed by Command.
        #
        # == Single-Pass Design
        #
        # Diffs are unbounded user input - a large PR could have thousands of changed lines across
        # many files. To minimize performance impact, this resolver processes each diff entry in a
        # single pass, resolving all pending locations for a path simultaneously as we iterate
        # through the diff lines.
        #
        # This approach means O(n) where n = diff lines, rather than O(n * m) where m = locations.
        # Locations are removed from the pending list as they're resolved, so we can exit early
        # once all locations for a file are found.
        #
        # Called by Command during the diff resolution stage.
        class DiffResolver
          sig do
            params(
              diff_loader: Positioner::Loaders::Diffs,
              base_commit_oid: String,
              head_commit_oid: String,
            ).void
          end
          def initialize(diff_loader:, base_commit_oid:, head_commit_oid:)
            @diff_loader = diff_loader
            @base_commit_oid = base_commit_oid
            @head_commit_oid = head_commit_oid
            @pending_locations = T.let([], T::Array[T.any(Locations::File, Locations::Line, Locations::Position)])
            @pending_identifiers = T.let(Set.new, T::Set[String])
            @results = T.let({}, T::Hash[String, Results::Diff])
          end

          # Enqueue a location for resolution (no I/O).
          # Locations already resolved are skipped, allowing multiple add/load cycles.
          sig { params(location: Types::UnresolvedLocation).void }
          def add_to_diff_batch(location)
            case location
            when Locations::Invalid
              nil # No-op for invalid locations
            when Locations::Line, Locations::File, Locations::Position
              key = identifier_for(location)

              # Skip if already resolved or already pending
              return if @results.key?(key)
              return if @pending_identifiers.include?(key)

              @pending_locations << location
              @pending_identifiers << key

              # Add to diff loader for batch loading
              @diff_loader.add_to_batch(
                base_commit_oid: @base_commit_oid,
                head_commit_oid: @head_commit_oid,
                path: location.path,
              )
            else
              T.absurd(location)
            end
          end

          # Fetch result for a location
          sig { params(location: Types::UnresolvedLocation).returns(Results::Diff) }
          def fetch(location)
            case location
            when Locations::Invalid
              Results::Diff.failure(outcome: Enums::Outcome::DiffNotLoaded)
            when Locations::Line, Locations::File, Locations::Position
              get(location) || Results::Diff.failure(outcome: Enums::Outcome::DiffNotLoaded)
            else
              T.absurd(location)
            end
          end

          # Batch load all pending locations (single-pass per path).
          # Safe to call multiple times; no-op if no pending locations.
          sig { void }
          def load_diffs!
            return if @pending_locations.empty?

            # Load all diffs
            @diff_loader.load_batch!

            # Group locations by path for single-pass processing
            locations_by_path = @pending_locations.group_by(&:path)

            locations_by_path.each do |path, locations|
              entry_result = @diff_loader.entry_for(
                base_commit_oid: @base_commit_oid,
                head_commit_oid: @head_commit_oid,
                path:,
              )

              case entry_result
              when GitHub::Diff::Entry
                resolve_locations_with_entry(locations, entry_result)
              when CommentPosition::Errors::Path
                # Path not in diff - this is NOT a failure, just means the file wasn't changed
                # The processor will decide what to do based on only_changed_files flag
                resolve_locations_not_in_diff(locations, path)
              when CommentPosition::Errors::DiffNotLoaded
                resolve_locations_with_failure(locations, Enums::Outcome::DiffNotLoaded)
              when CommentPosition::Errors::DiffNotValid
                resolve_locations_with_failure(locations, Enums::Outcome::DiffInvalid)
              when CommentPosition::Errors::GitUnavailable
                resolve_locations_with_failure(locations, Enums::Outcome::GitUnavailable)
              else
                T.absurd(entry_result)
              end
            end

            @pending_locations.clear
            @pending_identifiers.clear
          end

          # Check if a path is in the loaded diff
          sig { params(path: String).returns(T::Boolean) }
          def path_in_diff?(path:)
            entry_result = @diff_loader.entry_for(
              base_commit_oid: @base_commit_oid,
              head_commit_oid: @head_commit_oid,
              path:,
            )
            entry_result.is_a?(GitHub::Diff::Entry)
          end

          private

          # Resolves all locations for a single diff entry in one pass through the diff lines.
          #
          # == Algorithm Overview
          #
          # 1. Separate locations by type (file, line, position) for efficient processing
          # 2. Resolve file locations immediately (they don't need line iteration)
          # 3. Iterate through diff lines exactly once, resolving line/position locations as we go
          # 4. Track first/last line numbers seen to detect "outside diff" locations
          # 5. Remove resolved locations from pending lists to enable early exit
          #
          # == Line Position Tracking
          #
          # We track first_*_line_seen and last_*_line_seen for both sides (base/head) to:
          # - Detect lines before the first hunk (before any changes)
          # - Detect lines between hunks (unchanged gap regions)
          # - Detect lines after the last hunk (after all changes)
          # - Calculate equivalent line numbers on the opposite side for unchanged regions
          #
          # == Early Exit Optimization
          #
          # By using `reject!` to remove resolved locations from pending lists, we can break
          # out of the diff iteration as soon as all locations are resolved. This is critical
          # for performance when resolving a small number of locations in a large diff.
          sig { params(locations: T::Array[Types::UnresolvedLocation], entry: GitHub::Diff::Entry).void }
          def resolve_locations_with_entry(locations, entry)
            line_locations = T.let([], T::Array[Locations::Line])
            position_locations = T.let([], T::Array[Locations::Position])

            locations.each do |location|
              case location
              when Locations::File
                # Resolve file locations immediately
                set(location, Results::Diff.new(
                  match_type: Enums::MatchType::Exact,
                  base_path: entry.a_path,
                  head_path: entry.b_path,
                  outcome: Enums::Outcome::Current,
                ))
              when Locations::Line
                line_locations << location
              when Locations::Position
                position_locations << location
              when Locations::Invalid
                next
              else
                T.absurd(location)
              end
            end

            # Handle too_big entries - we can't iterate through the diff content
            if entry.too_big?
              # Line locations get a "matched but too big" result - we know the path matches
              # but can't determine exact position. We use ContentTooLarge outcome so results
              # builders can decide behavior based on input type (error for Blobs, outdated for others).
              result = Results::Diff.new(
                match_type: Enums::MatchType::NotInDiff,
                base_path: entry.a_path,
                head_path: entry.b_path,
                outcome: Enums::Outcome::ContentTooLarge,
              )

              line_locations.each { set(_1, result) }

              # Position locations must fail - we can't resolve a diff position without content
              result = Results::Diff.failure(outcome: Enums::Outcome::ContentTooLarge)

              position_locations.each { set(_1, result) }

              return
            end

            return if line_locations.empty? && position_locations.empty?

            # Working copies of location lists - we remove locations as they're resolved
            # to enable early exit from the diff iteration loop
            pending_line_locations = line_locations.dup
            pending_position_locations = position_locations.dup
            diff_hunk = T.let(0, Integer)

            # Track the first and last line number seen on each side of the diff.
            # This is essential for handling locations outside the diff hunks:
            #
            # - first_*_line_seen: Detects locations before the first hunk. If a requested
            #   line is less than this, it's in unchanged content before any modifications.
            #
            # - last_*_line_seen: Detects locations after the last hunk. If a requested line
            #   is greater than this after iteration completes, it's in unchanged content
            #   after all modifications.
            #
            # Both values are also used to calculate equivalent line numbers on the opposite
            # side. In unchanged regions, the offset between base and head lines is consistent.
            first_left_line_seen = T.let(nil, T.nilable(Integer))
            first_right_line_seen = T.let(nil, T.nilable(Integer))
            last_left_line_seen = T.let(nil, T.nilable(Integer))
            last_right_line_seen = T.let(nil, T.nilable(Integer))

            # Hunk headers (@@ -a,b +c,d @@) create gaps in the diff where unchanged lines
            # are not shown. When we see the first content line after a hunk header, we check
            # if any pending locations fall in the gap between the previous hunk's last line
            # and this hunk's first line. Those lines exist but aren't in the diff.
            just_saw_hunk_header = T.let(false, T::Boolean)

            entry.each_line do |diff_line|
              diff_line = T.let(diff_line, GitHub::Diff::Line)

              # Check position locations on ALL lines including hunk headers.
              # The old code path (blob_positioning_for) matches positions on hunk headers,
              # so we must do the same for compatibility. While hunk headers aren't typical
              # comment targets, the position index includes them.
              pending_position_locations.reject! do |location|
                if resolved_position = resolve_position(location, diff_line, entry, diff_hunk)
                  set(location, resolved_position, diff_line:)
                end
              end

              if diff_line.hunk?
                diff_hunk += 1
                just_saw_hunk_header = true
                next
              end

              # Between-hunk gap detection:
              #
              # Diffs only show changed lines plus a few lines of context. Large gaps of
              # unchanged code between hunks are collapsed. When we encounter the first
              # content line of a new hunk (hunk 2+), we can detect locations that fall
              # in this gap by checking if they're between last_*_line_seen (end of
              # previous hunk) and current_* (start of this hunk).
              #
              # These lines are valid but not visible in the diff, so we resolve them
              # as NotInDiff with calculated equivalent positions on both sides.
              if just_saw_hunk_header && diff_hunk > 1
                current_left = diff_line.left
                current_right = diff_line.right

                pending_line_locations.reject! do |location|
                  line = location.line
                  targeting_base = location.targeting_base?
                  last_seen = targeting_base ? last_left_line_seen : last_right_line_seen
                  current = targeting_base ? current_left : current_right

                  # If the line is after the last line of previous hunk but before the first line of this hunk,
                  # it's between hunks and should be NotInDiff
                  if last_seen && current && line > last_seen && line < current
                    # Calculate the equivalent line on the other side
                    # Lines between hunks are unchanged, so the offset from last seen line applies
                    offset_from_last = line - last_seen

                    if targeting_base
                      # Left side (base) - calculate equivalent head line
                      calculated_base_line = line
                      calculated_head_line = last_right_line_seen ? last_right_line_seen + offset_from_last : nil
                    else
                      # Right side (head) - calculate equivalent base line
                      calculated_base_line = last_left_line_seen ? last_left_line_seen + offset_from_last : nil
                      calculated_head_line = line
                    end

                    set(location, Results::Diff.new(
                      match_type: Enums::MatchType::NotInDiff,
                      base_path: entry.a_path,
                      head_path: entry.b_path,
                      base_line: calculated_base_line,
                      head_line: calculated_head_line,
                      outcome: Enums::Outcome::OutsideDiff,
                    ))
                  end
                end
              end

              just_saw_hunk_header = false

              # Track first and last line on each side
              first_left_line_seen ||= diff_line.left
              first_right_line_seen ||= diff_line.right
              last_left_line_seen = diff_line.left if diff_line.left
              last_right_line_seen = diff_line.right if diff_line.right

              # Resolve line locations
              pending_line_locations.reject! do |location|
                first_line_seen = location.targeting_base? ? first_left_line_seen : first_right_line_seen
                if resolved_line = resolve_line(location, diff_line, entry, diff_hunk, first_line_seen)
                  set(location, resolved_line)
                end
              end

              # Early exit: Once all locations are resolved, stop iterating through the diff.
              # This is critical for performance - we don't need to process the remaining
              # potentially thousands of diff lines if we've already found what we need.
              break if pending_line_locations.empty? && pending_position_locations.empty?
            end

            # Position locations are indexed by diff position (1-based offset from diff start).
            # If we iterated through the entire diff without finding the position, it means
            # the position no longer exists - likely the line was removed in a later commit
            # or the diff has changed.
            pending_position_locations.each do |location|
              set(location, Results::Diff.failure(outcome: Enums::Outcome::LineRemoved))
            end

            # Line locations remaining after iteration are outside all hunks. This happens when:
            # 1. Line is before first_*_line_seen (before any changed content)
            # 2. Line is after last_*_line_seen (after all changed content)
            #
            # These are valid lines in unchanged regions. We calculate the equivalent line
            # on the opposite side using the offset from the nearest hunk boundary, since
            # unchanged regions maintain consistent line number offsets between base and head.
            pending_line_locations.each do |location|
              line = location.line
              targeting_base = location.targeting_base?
              first_seen = targeting_base ? first_left_line_seen : first_right_line_seen
              last_seen = targeting_base ? last_left_line_seen : last_right_line_seen

              # Calculate equivalent line on the other side
              if first_seen && line < first_seen
                # Before first hunk - lines are unchanged, same offset applies
                offset = first_seen - line

                if targeting_base
                  calculated_base_line = line
                  calculated_head_line = first_right_line_seen ? first_right_line_seen - offset : line
                else
                  calculated_base_line = first_left_line_seen ? first_left_line_seen - offset : line
                  calculated_head_line = line
                end
              elsif last_seen && line > last_seen
                # After last hunk - lines are unchanged, same offset applies
                offset = line - last_seen

                if targeting_base
                  calculated_base_line = line
                  calculated_head_line = last_right_line_seen ? last_right_line_seen + offset : nil
                else
                  calculated_base_line = last_left_line_seen ? last_left_line_seen + offset : nil
                  calculated_head_line = line
                end
              else
                # No hunk context available at all
                calculated_base_line = targeting_base ? line : nil
                calculated_head_line = targeting_base ? nil : line
              end

              set(location, Results::Diff.new(
                match_type: Enums::MatchType::NotInDiff,
                base_path: entry.a_path,
                head_path: entry.b_path,
                base_line: calculated_base_line,
                head_line: calculated_head_line,
                outcome: Enums::Outcome::OutsideDiff,
              ))
            end
          end

          # Attempts to resolve a line location against the current diff line.
          #
          # Returns:
          # - Results::Diff with Exact match if this diff line matches the location
          # - Results::Diff with Closest match if we've passed the target line
          # - nil if we haven't reached the target line yet (keep iterating)
          #
          # The "closest" match case handles scenarios where the exact line number doesn't
          # appear in the diff (e.g., it was a deletion). We return the next visible line
          # as the closest anchor point.
          sig do
            params(
              location: Locations::Line,
              diff_line: GitHub::Diff::Line,
              entry: GitHub::Diff::Entry,
              hunk: Integer,
              first_line_seen: T.nilable(Integer)
            ).returns(T.nilable(Results::Diff))
          end
          def resolve_line(location, diff_line, entry, hunk, first_line_seen)
            line = location.line

            # Check the appropriate side of the diff based on what the location targets
            diff_side_line = location.targeting_base? ? diff_line.left : diff_line.right

            # nil means this side doesn't have a line number (e.g., addition has no left line)
            return nil if diff_side_line.nil?

            if diff_side_line == line
              line_type = if diff_line.addition?
                Enums::LineType::Addition
              elsif diff_line.deletion?
                Enums::LineType::Deletion
              else
                Enums::LineType::Context
              end

              Results::Diff.exact(
                position: diff_line.position,
                base_line: diff_line.left,
                head_line: diff_line.right,
                base_path: entry.a_path,
                head_path: entry.b_path,
                hunk:,
                line_type:,
              )
            elsif diff_side_line > line && first_line_seen && line >= first_line_seen
              # Only create closest match if the line is within the range we've seen in the diff
              # Lines before the first line of the diff are "outside diff", not closest
              Results::Diff.new(
                match_type: Enums::MatchType::Closest,
                position: nil,
                base_line: diff_line.left,
                head_line: diff_line.right,
                base_path: entry.a_path,
                head_path: entry.b_path,
                hunk:,
                outcome: Enums::Outcome::Unknown,
              )
            else
              nil
            end
          end

          # Attempts to resolve a position-based location against the current diff line.
          #
          # Position is a 1-based index into the diff text, counting from the first line
          # after the diff header. This is the legacy format used by the GitHub API and
          # stored in older comments.
          #
          # Unlike line locations, positions are exact - either the position exists in
          # the diff or it doesn't. There's no "closest" fallback because the position
          # is an index into the diff itself, not a line number in the file.
          sig { params(location: Locations::Position, diff_line: GitHub::Diff::Line, entry: GitHub::Diff::Entry, hunk: Integer).returns(T.nilable(Results::Diff)) }
          def resolve_position(location, diff_line, entry, hunk)
            position_value = location.position

            return nil if diff_line.position != position_value

            # For deletions, the line exists on the left (base) side; for additions/context, use the right (head) side
            line = diff_line.deletion? ? diff_line.left : diff_line.right

            return nil if line.nil?

            line_type = if diff_line.addition?
              Enums::LineType::Addition
            elsif diff_line.deletion?
              Enums::LineType::Deletion
            else
              Enums::LineType::Context
            end

            Results::Diff.exact(
              position: position_value,
              base_path: entry.a_path,
              head_path: entry.b_path,
              base_line: diff_line.left,
              head_line: diff_line.right,
              hunk:,
              line_type:,
            )
          end

          sig { params(locations: T::Array[Types::UnresolvedLocation], outcome: Results::Diff::Outcomes).void }
          def resolve_locations_with_failure(locations, outcome)
            failure = Results::Diff.failure(outcome:)
            locations.each do |location|
              case location
              when Locations::Invalid
                next
              when Locations::Line, Locations::File, Locations::Position
                set(location, failure)
              else
                T.absurd(location)
              end
            end
          end

          # Resolve locations for paths not in the diff (unchanged files)
          sig { params(locations: T::Array[Types::UnresolvedLocation], path: String).void }
          def resolve_locations_not_in_diff(locations, path)
            locations.each do |location|
              case location
              when Locations::Invalid
                next
              when Locations::Line
                set(location, Results::Diff.new(
                  match_type: Enums::MatchType::NotInDiff,
                  outcome: Enums::Outcome::OutsideDiff,
                  base_path: location.targeting_base? ? path : nil,
                  head_path: location.targeting_base? ? nil : path,
                  base_line: location.targeting_base? ? location.line : nil,
                  head_line: location.targeting_base? ? nil : location.line,
                ))
              when Locations::File
                set(location, Results::Diff.new(
                  match_type: Enums::MatchType::NotInDiff,
                  outcome: Enums::Outcome::OutsideDiff,
                  base_path: location.targeting_base? ? path : nil,
                  head_path: location.targeting_base? ? nil : path,
                ))
              when Locations::Position
                # Position requires a diff to resolve - if path is not in diff, position cannot be resolved
                set(location, Results::Diff.failure(
                  outcome: Enums::Outcome::PathRemoved
                ))
              else
                T.absurd(location)
              end
            end
          end

          # Stores a result for a location in the results cache.
          # For Position locations resolved with a diff_line, also stores under the equivalent
          # Line identifier so subsequent lookups by Line find the cached result.
          sig do
            params(
              location: T.any(Locations::Line, Locations::File, Locations::Position),
              result: Results::Diff,
              diff_line: T.nilable(GitHub::Diff::Line),
            ).returns(T::Boolean)
          end
          def set(location, result, diff_line: nil)
            @results[identifier_for(location)] = result

            # For resolved Position locations, also cache under the equivalent Line identifier
            if location.is_a?(Locations::Position) && diff_line && (line_id = line_identifier_for_position(location, diff_line))
              @results[line_id] = result
            end

            true
          end

          # Retrieves a cached result for a location, or nil if not found.
          sig { params(location: T.any(Locations::Line, Locations::File, Locations::Position)).returns(T.nilable(Results::Diff)) }
          def get(location) = @results[identifier_for(location)]

          # Generates a cache key for a location. Centralizes key generation so we can
          # store results under multiple keys (e.g., Position and equivalent Line).
          sig { params(location: T.any(Locations::Line, Locations::File, Locations::Position)).returns(String) }
          def identifier_for(location)
            case location
            when Locations::Line
              "line:#{location.path}:#{location.line}:#{location.commit_oid}"
            when Locations::File
              "file:#{location.path}"
            when Locations::Position
              "position:#{location.path}:#{location.position}"
            else
              T.absurd(location)
            end
          end

          # Computes the Line identifier that corresponds to a resolved Position.
          # This allows caching the result under both identifiers so subsequent
          # lookups by Line will find the cached Position result.
          sig { params(position: Locations::Position, diff_line: GitHub::Diff::Line).returns(T.nilable(String)) }
          def line_identifier_for_position(position, diff_line)
            # For deletions, the line exists on the left (base) side
            # For additions/context, use the right (head) side
            if diff_line.deletion?
              line = diff_line.left
              commit_oid = @base_commit_oid
            else
              line = diff_line.right
              commit_oid = @head_commit_oid
            end

            return nil unless line

            "line:#{position.path}:#{line}:#{commit_oid}"
          end
        end
      end
    end
  end
end
