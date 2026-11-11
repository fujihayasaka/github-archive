# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      # Orchestrates the positioning pipeline for pull request comments.
      class Processor
        sig do
          params(
            inputs: T::Array[Positioner::Inputs::Types],
            command: Command,
            only_changed_files: T::Boolean,
          ).void
        end
        def initialize(inputs:, command:, only_changed_files: false)
          @inputs = inputs
          @command = command
          @only_changed_files = only_changed_files
          @requests = T.let({}, T::Hash[Positioner::Inputs::Types, Types::Request])
        end

        # The pipeline transforms input locations through these steps:
        #   1. generate_requests!       - Convert inputs to typed Request objects (no I/O)
        #   2. preload_source_diffs!    - Batch GitRPC calls for steps 3-4
        #   3. resolve_positions!       - Convert Position to Line/Invalid (diff-relative → absolute)
        #   4. resolve_source_contexts! - Load original_position for repositioning
        #   5. retarget_locations!      - Track line movement from source to target range (SpokesAPI)
        #   6. preload_target_diffs!    - Batch GitRPC calls for steps 7-8
        #   7. resolve_diff_contexts!   - Resolve context metadata for all valid locations
        #   8. handle_unchanged_files!  - Validate blobs or reject based on only_changed_files
        #
        # State flows through Locations::State objects which track:
        #   - input:  The original location from the request
        #   - source: The location at source commit range (for original_position)
        #   - target: The final resolved location at target commit range
        #   - error:  Any error encountered during processing
        sig { returns(T::Array[T.any(Types::Result, CommentPosition::Errors)]) }
        def call
          generate_requests!
          preload_source_diffs!
          resolve_positions!
          resolve_source_contexts!
          retarget_locations!
          preload_target_diffs!
          resolve_diff_contexts!
          handle_unchanged_files!

          # Build final results - Requests::Invalid returns error, others return Result structs
          @inputs.map do |input|
            request = @requests[input]
            if request.nil?
              CommentPosition::Errors::Parameter.new(input: "no request found")
            elsif request.is_a?(Requests::Invalid)
              request.error
            else
              request.to_result
            end
          end
        end

        protected

        sig { void }
        def generate_requests!
          @inputs.each do |input|
            @requests[input] = case input
            when Positioner::Inputs::DiffRelative
              Requests::Factories::DiffRelative.build(input:, target_range:)
            when Positioner::Inputs::Blobs
              Requests::Factories::Blobs.build(input:, target_range:)
            when Positioner::Inputs::Positioning
              Requests::Factories::Positioning.build(input:, target_range:)
            when Positioner::Inputs::ThreadColumns
              Requests::Factories::ThreadColumns.build(input:, target_range:)
            else
              T.absurd(input)
            end
          end
        end

        sig { void }
        def preload_source_diffs!
          # Collect Position locations (for Step 3)
          @requests.each_value.flat_map(&:states).each do |state|
            case input = state.input
            when Locations::Position
              @command.add_to_diff_batch(input, commit_range: input.commit_range)
            end
          end

          # Collect Line/File locations needing retargeting (for Step 4)
          locations_needing_retargeting.each do |location, state|
            @command.add_to_diff_batch(location, commit_range: state.source_range)
          end

          @command.load_diffs!
        end

        # Position is a diff-relative offset that must be converted to absolute line numbers.
        # Invalid positions (not found in diff) are marked with errors.
        sig { void }
        def resolve_positions!
          # Group Position locations by commit range for batch resolution
          locations = T.let({}, T::Hash[Types::CommitRange, T::Hash[Locations::Position, Locations::State]])

          @requests.each_value.flat_map(&:states).each do |state|
            case input = state.input
            when Locations::Position
              (locations[input.commit_range] ||= {})[input] = state
            end
          end

          # Resolve each batch (diffs already loaded via preload_source_diffs!)
          locations.each do |commit_range, positions_and_states|
            @command.resolve_positions(positions_and_states.keys, commit_range:).each do |source_location, target_location|
              next unless state = positions_and_states[source_location]

              if target_location.is_a?(Locations::Invalid)
                state.error = CommentPosition::Errors.from_outcome(
                  outcome: target_location.outcome,
                  path: source_location.path,
                  position: source_location.position,
                )
              end

              state.source = target_location
            end
          end
        end

        # Load diff context at original range for repositioning. Provides original_position.
        # Position inputs already have context from resolve_positions!; Line/File inputs load here.
        sig { void }
        def resolve_source_contexts!
          locations = locations_needing_retargeting
          return if locations.empty?

          # Resolve contexts for each commit range.
          # For Position inputs resolved in Step 3, the result is cached under both the
          # Position and equivalent Line identifiers, so no re-batching is needed.
          locations.group_by { |_, state| state.source_range }.each do |commit_range, grouped|
            source_locations = grouped.map(&:first)
            @command.resolve_contexts(source_locations, commit_range:).each do |source_location, target_location|
              locations[source_location]&.source = target_location
            end
          end
        end

        # Track how lines moved between source and target ranges via git diff.
        sig { void }
        def retarget_locations!
          locations = locations_needing_retargeting
          return if locations.empty?

          grouped = locations.keys.group_by { |loc| locations.fetch(loc).source_range }

          # Phase 1: Add ALL locations across ALL source_range groups to the batch
          # before executing. BatchReadDiffPositions#execute is memoized, so all
          # items must be added before the single execute call.
          grouped.each do |source_range, source_locations|
            next if source_range == target_range # skip identical ranges
            @command.add_to_retarget_batch(source_locations, to: target_range)
          end

          # Phase 2: Execute the batch once for all groups
          @command.load_retarget_batch!

          # Phase 3: Fetch results per-group
          grouped.each do |source_range, source_locations|
            @command.retarget(source_locations, from: source_range, to: target_range).each do |source_location, target_location|
              locations[source_location]&.target = target_location
            end
          end
        end

        sig { void }
        def preload_target_diffs!
          eligible_locations.each_key do |location|
            @command.add_to_diff_batch(location, commit_range: target_range)
          end

          @command.load_diffs!
        end

        # Resolve context metadata (position, hunk, line type) for valid locations.
        sig { void }
        def resolve_diff_contexts!
          locations = eligible_locations
          return if locations.empty?

          @command.resolve_contexts(locations.keys, commit_range: target_range).each do |source_location, target_location|
            next unless state = locations[source_location]

            state.target = target_location

            # Also set source if not already set (for non-Position inputs that skipped Step 3/4)
            # This ensures source_context is available for result building
            state.source ||= target_location
          end

          # Generate compressed_diff_hunk for requests that need it.
          # The hunk is a snippet of the diff around the comment position,
          # used for display in the UI and email notifications.
          @requests.each_value do |request|
            next unless request.needs_diff_hunk?

            end_state = request.states.first
            next unless end_state&.valid?

            context = end_state.location.context
            next unless context.resolved?

            next unless (position = context.position) && (path = end_state.path)

            case request
            when Requests::Line, Requests::Multiline
              request.compressed_diff_hunk = @command.diff_hunk_for(path:, position:, at_range: target_range)
            end
          end
        end

        # Handle lines outside the diff. If only_changed_files: mark invalid; else validate blobs.
        sig { void }
        def handle_unchanged_files!
          locations = unchanged_locations
          return if locations.empty?

          if @only_changed_files
            locations.each do |location, state|
              # Determine if the file is in the diff based on whether both paths are set.
              # When a file IS in the diff, the diff resolver provides BOTH base_path and head_path.
              # When a file is NOT in the diff, only the targeted side's path is set.
              context = state.location.context
              file_in_diff = context.base_path && context.head_path
              line = location.is_a?(Locations::Line) ? location.line : nil

              # Use LineRemoved for files in the diff (the path is valid, just the line is
              # outside the changed hunks). Use PathNotFound for files not in the diff at all.
              outcome = file_in_diff ? Enums::Outcome::LineRemoved : Enums::Outcome::PathNotFound

              state.target = Locations::Invalid.new(
                outcome:,
                path: location.path,
                commit_oid: location.commit_oid,
                commit_range: target_range,
                line:,
                context: Locations::Context.failure(
                  outcome:,
                  failed_from: :only_changed_files,
                ),
              )

              state.error = CommentPosition::Errors.from_outcome(
                outcome:,
                path: location.path,
                line:,
              )
            end
          else
            # Split locations into two groups:
            # 1. Locations where file is in diff but line is outside hunks - no blob validation needed
            # 2. Locations where file is not in diff at all - need blob validation
            #
            # When a file IS in the diff, the diff entry provides BOTH base_path and head_path.
            # When a file is NOT in the diff, resolve_locations_not_in_diff only sets the path
            # on the side being targeted (base_path OR head_path, not both).
            file_in_diff_locations = T.let({}, T::Hash[T.any(Locations::Line, Locations::File), Locations::State])
            file_not_in_diff_locations = T.let({}, T::Hash[T.any(Locations::Line, Locations::File), Locations::State])

            locations.each do |location, state|
              context = state.location.context
              # If context has BOTH base_path and head_path, the file was found in the diff
              if context.base_path && context.head_path
                file_in_diff_locations[location] = state
              else
                file_not_in_diff_locations[location] = state
              end
            end

            # For locations where file is in diff, the target is already set correctly
            # (line is just outside the hunks). No additional validation needed.
            # The location already has NotInDiff context from Step 5.

            # For locations where file is NOT in diff, validate blobs
            if file_not_in_diff_locations.any?
              @command.validate_outside_diff_blobs(file_not_in_diff_locations.keys, commit_range: target_range).each do |source_location, target_location|
                next unless state = file_not_in_diff_locations[source_location]

                case target_location
                when Locations::Invalid
                  line = source_location.is_a?(Locations::Line) ? source_location.line : nil
                  state.error = CommentPosition::Errors.from_outcome(
                    outcome: target_location.outcome,
                    path: source_location.path,
                    line:,
                  )
                end

                state.target = target_location
              end
            end
          end
        end

        private

        sig { returns(Types::CommitRange) }
        def target_range = @command.target_range

        # Locations that need to be repositioned from source to target range.
        # Excludes up-to-date locations (source == target) and invalid locations.
        # Uses source location if available (from Step 2), otherwise input.
        sig { returns(T::Hash[T.any(Locations::Line, Locations::File), Locations::State]) }
        def locations_needing_retargeting
          @requests.values.flat_map(&:states).each_with_object({}) do |state, hash|
            next if state.up_to_date?
            next unless state.repositionable?

            case source_location = (state.source || state.input)
            when Locations::Line, Locations::File
              hash[source_location] = state
            end
          end
        end

        # All valid (non-Invalid) locations with their states.
        # Used for loading diff contexts in Step 7.
        sig { returns(T::Hash[T.any(Locations::Line, Locations::File), Locations::State]) }
        def eligible_locations
          @requests.values.flat_map(&:states).each_with_object({}) do |state, hash|
            next unless state.valid?

            case source_location = state.location
            when Locations::Line, Locations::File
              hash[source_location] = state
            end
          end
        end

        # Valid locations that are outside the diff (unchanged files).
        # These need blob validation in Step 8 to ensure the path/line exists.
        #
        # Excludes ContentTooLarge locations: these files ARE in the diff but the diff
        # content is too large to iterate. They should not be treated as "unchanged" -
        # the result builder will detect ContentTooLarge via Context#to_error and
        # return an appropriate DiffEntryTooBig error for creation inputs.
        sig { returns(T::Hash[T.any(Locations::Line, Locations::File), Locations::State]) }
        def unchanged_locations
          eligible_locations.select do |_location, state|
            context = state.location.context
            context.match_type == Enums::MatchType::NotInDiff &&
              context.outcome != Enums::Outcome::ContentTooLarge
          end
        end
      end
    end
  end
end
