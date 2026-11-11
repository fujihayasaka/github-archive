# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioning
      # Command class that encapsulates all I/O operations for the Positioning module.
      class Command
        sig { returns(Types::CommitRange) }
        attr_reader :target_range

        sig do
          params(
            repository: Repository,
            target_range: Types::CommitRange,
            diffs: T::Array[GitHub::Diff],
          ).void
        end
        def initialize(repository:, target_range:, diffs: [])
          @repository = repository
          @target_range = T.let(target_range, Types::CommitRange)
          @diff_loader = T.let(Positioner::Loaders::Diffs.new(repository:, diffs:), Positioner::Loaders::Diffs)
          @blob_loader = T.let(Positioner::Loaders::BlobsAndLines.new(repository:), Positioner::Loaders::BlobsAndLines)
          @diff_positions_loader = T.let(Positioner::Loaders::DiffPositions.new(repository:), Positioner::Loaders::DiffPositions)
          @diff_resolvers = T.let(Loaders::DiffResolvers.new(diff_loader: @diff_loader), Loaders::DiffResolvers)
        end

        # Append a location and commit range to be included in the batch diff loading.
        sig { params(location: Types::UnresolvedLocation, commit_range: Types::CommitRange).void }
        def add_to_diff_batch(location, commit_range:)
          @diff_resolvers.add_to_diff_batch(location, range: commit_range)
        end

        # Invoke batch loading of all outstanding diffs.
        sig { void }
        def load_diffs!
          @diff_resolvers.load_diffs!
        end

        # Resolve Position locations to Line/Invalid at a commit range.
        # Position is diff-relative (1-based offset in diff output) and must be converted to Line.
        sig do
          params(
            positions: T::Array[Locations::Position],
            commit_range: Types::CommitRange,
          ).returns(T::Hash[Locations::Position, Types::ResolvedLocation])
        end
        def resolve_positions(positions, commit_range:)
          return {} if positions.empty?

          # Fetch results from already-loaded diffs
          positions.each_with_object({}) do |position, hash|
            hash[position] = Locations::Resolver.new(
              location: position,
              target_range: commit_range,
              reposition_result: nil,
              diff_result: @diff_resolvers.fetch(position, range: commit_range),
              blob_result: nil,
            ).to_location
          end
        end

        # Add locations to the retarget batch for later execution.
        # Must be called before load_retarget_batch! to ensure all items are
        # included in the batch before the SpokesAPI call.
        sig do
          params(
            locations: T::Array[T.any(Locations::Line, Locations::File)],
            to: Types::CommitRange,
          ).void
        end
        def add_to_retarget_batch(locations, to:)
          target_base_oid, target_head_oid = to

          locations.each do |location|
            target_commit_oid = location.targeting_base? ? target_base_oid : target_head_oid

            @diff_positions_loader.add_to_batch(
              target_commit_oid:,
              source_commit_oid: location.commit_oid,
              source_path: location.path,
              line: (location.line if location.is_a?(Locations::Line)),
            )
          end
        end

        # Execute the retarget batch. Must be called after all items have been
        # added via add_to_retarget_batch.
        sig { void }
        def load_retarget_batch!
          @diff_positions_loader.load_batch!
        end

        # Retarget locations from source to target commit range.
        # Uses DiffPositions API to track how lines move between commits.
        # Items must be pre-loaded via add_to_retarget_batch + load_retarget_batch!
        sig do
          params(
            locations: T::Array[T.any(Locations::Line, Locations::File)],
            from: Types::CommitRange,
            to: Types::CommitRange,
          ).returns(T::Hash[T.any(Locations::Line, Locations::File), Types::ResolvedLocation])
        end
        def retarget(locations, from:, to:)
          return {} if locations.empty?

          # If ranges are the same, no retargeting needed - return locations as-is
          if from == to
            return locations.each_with_object({}) { |location, hash| hash[location] = location }
          end

          target_base_oid, target_head_oid = to

          # Build results from pre-loaded batch data
          locations.each_with_object({}) do |location, hash|
            target_commit_oid = location.targeting_base? ? target_base_oid : target_head_oid

            hash[location] = Locations::Resolver.new(
              location:,
              target_range: to,
              reposition_result: reposition_location(location, target_commit_oid:),
              diff_result: nil,
              blob_result: nil,
            ).to_location
          end
        end

        # Resolve diff contexts for locations at a commit range.
        # Returns locations with Context populated from diff matching.
        sig do
          params(
            locations: T::Array[T.any(Locations::Line, Locations::File)],
            commit_range: Types::CommitRange,
          ).returns(T::Hash[T.any(Locations::Line, Locations::File), Types::ResolvedLocation])
        end
        def resolve_contexts(locations, commit_range:)
          return {} if locations.empty?

          # Fetch results from already-loaded diffs
          locations.each_with_object({}) do |location, hash|
            hash[location] = Locations::Resolver.new(
              location:,
              target_range: commit_range,
              reposition_result: nil,
              diff_result: @diff_resolvers.fetch(location, range: commit_range),
              blob_result: nil,
            ).to_location
          end
        end

        # Validate that paths/lines exist in blobs outside the diff.
        # Used for comments on unchanged files when only_changed_files is false.
        sig do
          params(
            locations: T::Array[T.any(Locations::Line, Locations::File)],
            commit_range: Types::CommitRange,
          ).returns(T::Hash[T.any(Locations::Line, Locations::File), Types::ResolvedLocation])
        end
        def validate_outside_diff_blobs(locations, commit_range:)
          return {} if locations.empty?

          # Add all locations to batch
          locations.each do |location|
            @blob_loader.add_to_batch(
              commit_oid: location.commit_oid,
              path: location.path,
              line: location.line,
            )
          end

          # Single batch load
          @blob_loader.load_batch!

          # Build results
          locations.each_with_object({}) do |location, hash|
            blob_result = validate_via_blobs_and_lines(location)

            diff_result = case location
            when Locations::Line
              Loaders::Results::Diff.new(
                match_type: Enums::MatchType::NotInDiff,
                outcome: Enums::Outcome::OutsideDiff,
                base_path: location.targeting_base? ? location.path : nil,
                base_line: location.targeting_base? ? location.line : nil,
                head_path: location.targeting_base? ? nil : location.path,
                head_line: location.targeting_base? ? nil : location.line,
              )
            when Locations::File
              Loaders::Results::Diff.new(
                match_type: Enums::MatchType::NotInDiff,
                outcome: Enums::Outcome::OutsideDiff,
                base_path: location.targeting_base? ? location.path : nil,
                head_path: location.targeting_base? ? nil : location.path,
              )
            else
              T.absurd(location)
            end

            hash[location] = Locations::Resolver.new(
              location:,
              target_range: commit_range,
              reposition_result: nil,
              diff_result:,
              blob_result:,
            ).to_location
          end
        end

        # Generate the compressed diff hunk for a path/position at a commit range.
        sig { params(path: String, position: Integer, at_range: Types::CommitRange).returns(T.nilable(String)) }
        def diff_hunk_for(path:, position:, at_range:)
          base_commit_oid, head_commit_oid = at_range
          entry = @diff_loader.entry_for(base_commit_oid:, head_commit_oid:, path:)

          return nil unless entry.is_a?(GitHub::Diff::Entry)
          return nil if entry.too_big?

          diff_lines = entry.lines
          excerpt = T.let([], T::Array[String])

          # Walk backwards from position to hunk header
          position.downto(0).each do |index|
            line = diff_lines[index]
            break if line.nil?
            excerpt.unshift(line)
            break if line.start_with?("@")
          end

          return nil if excerpt.empty?
          excerpt.join("\n")
        end

        # Check if a path is in the diff at a given range
        sig { params(path: String, commit_range: Types::CommitRange).returns(T::Boolean) }
        def path_in_diff?(path:, commit_range:)
          @diff_resolvers.path_in_diff?(path:, range: commit_range)
        end

        private

        # Fetch retargeted path/line and build reposition result in one step.
        sig do
          params(
            location: T.any(Locations::Line, Locations::File),
            target_commit_oid: String,
          ).returns(Loaders::Results::Reposition)
        end
        def reposition_location(location, target_commit_oid:)
          retargeted = @diff_positions_loader.fetch_path_and_line(
            target_commit_oid:,
            source_commit_oid: location.commit_oid,
            source_path: location.path,
            line: location.line,
          )

          path, line = retargeted.values_at(:path, :line)

          if path.nil? || (line && line < 0)
            error = line.nil? ? Enums::Outcome::PathRemoved : Enums::Outcome::LineRemoved
            Loaders::Results::Reposition.new(success: false, error:)
          else
            Loaders::Results::Reposition.success(path:, line:)
          end
        end

        # Validate a location's blob exists and build the result.
        sig { params(location: T.any(Locations::Line, Locations::File)).returns(Loaders::Results::Blob) }
        def validate_via_blobs_and_lines(location)
          result = @blob_loader.resolve(
            commit_oid: location.commit_oid,
            path: location.path,
            line: location.line,
          )

          case result
          when true
            Loaders::Results::Blob.valid
          when CommentPosition::Errors::Path
            Loaders::Results::Blob.path_not_found
          when CommentPosition::Errors::Line
            case location
            when Locations::Line
              Loaders::Results::Blob.line_out_of_range
            when Locations::File
              Loaders::Results::Blob.path_not_found
            end
          else
            T.absurd(result)
          end
        end
      end
    end
  end
end
