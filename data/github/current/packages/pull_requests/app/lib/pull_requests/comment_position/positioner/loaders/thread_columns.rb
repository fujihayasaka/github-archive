# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Positioner
      module Loaders
        # Efficiently loads thread column data by reusing loaded ActiveRecord relations
        # when available and falling back to targeted SQL queries when necessary.
        #
        # The ThreadColumns loader handles:
        # - Reusing pre-loaded thread collections to avoid redundant queries
        # - Extracting column data from ActiveRecord relations or arrays
        # - Combining data from multiple thread types (line and file threads)
        # - Converting raw database columns into structured input objects
        #
        # Supports injected thread collections for testing scenarios and handles
        # various thread subject types with appropriate defaults.
        class ThreadColumns
          include GitHub::Memoizer

          # Initialize the loader with pull request context and optional pre-loaded threads.
          # The threads parameter allows injecting specific thread collections for testing
          # or when threads are already loaded in memory.
          sig do
            params(
              pull_request: PullRequest,
              base_commit_oid: String,
              head_commit_oid: String,
              threads: T.nilable(T.any(T::Array[PullRequestReviewThread], ActiveRecord::AssociationRelation)), # Optional injected collection of threads.
            ).void
          end
          def initialize(pull_request:, base_commit_oid:, head_commit_oid:, threads: nil)
            @pull_request = pull_request
            @threads = threads
            @base_commit_oid = base_commit_oid
            @head_commit_oid = head_commit_oid
          end

          # Convert loaded thread column data into structured input objects for positioning.
          # Processes raw database columns, handles position parsing, and creates properly
          # typed input objects with default values for missing or invalid data.
          sig { returns(T::Array[Positioner::Inputs::ThreadColumns]) }
          def to_inputs
            thread_columns.filter_map do |columns|
              # Extract all required column values using the predefined column order
              identifier, path, commit_id, position, blob_position, blob_path, blob_commit_oid, left_blob, outdated,
              start_position_offset, subject_type, original_positioning, latest_positioning, original_commit_id,
              original_position, original_base_commit_id, original_start_commit_id, original_end_commit_id, compressed_diff_hunk =
                columns.values_at(*THREAD_COLUMNS)

              # Create the structured input object with all necessary positioning data
              Positioner::Inputs::ThreadColumns.new(
                base_commit_oid: @base_commit_oid,
                head_commit_oid: @head_commit_oid,
                subject_type: Enums::SubjectType.deserialize_with_default(subject_type, default: Enums::SubjectType::Line),
                original_positioning: Positions::Parser.parse_or_nil(original_positioning),
                latest_positioning: Positions::Parser.parse_or_nil(latest_positioning),
                identifier:, path:, commit_id:, position:, blob_position:, blob_path:, blob_commit_oid:,
                left_blob:, outdated:, start_position_offset:, original_commit_id:, original_base_commit_id:,
                original_start_commit_id:, original_end_commit_id:, original_position:, compressed_diff_hunk:,
              )
            end
          end

          protected

          THREAD_COLUMNS = %w[
            id path commit_id position blob_position blob_path blob_commit_oid left_blob outdated start_position_offset
            subject_type original_positioning latest_positioning original_commit_id original_position original_base_commit_id
            original_start_commit_id original_end_commit_id compressed_diff_hunk
          ].freeze

          # Intelligently load thread column data using the most efficient available method.
          # Prioritizes reusing loaded relations over database queries and combines data
          # from multiple sources when partially loaded to minimize database interactions.
          # Attempt to reuse any loaded relations to reduce how much DB interaction is occuring.
          sig { returns(T::Array[HashWithIndifferentAccess]) }
          memoize def thread_columns
            # Check if we have an injected ActiveRecord relation
            if @threads.is_a?(ActiveRecord::AssociationRelation)
              # Support utilizing loaded records or reusing an existing scope/relation.
              if @threads.loaded?
                # Data is already in memory, extract columns directly
                return to_column_hashes(@threads)
              else
                # Relation exists but not loaded, use efficient pluck query
                return pluck_from_relation(@threads)
              end
            elsif @threads.is_a?(Array)
              # If an array of threads are given, default to using just those.
              return to_column_hashes(@threads)
            elsif @pull_request.review_threads.loaded?
              # This is a complete relation, we can safely return if it's loaded.
              return to_column_hashes(@pull_request.review_threads)
            end

            # No pre-loaded data available, need to intelligently load from database
            threads = T.let([], T::Array[HashWithIndifferentAccess])
            load_from_database = T.let(false, T::Boolean)
            loaded_ids = T.let(Set.new, T::Set[Integer])

            # Attempt to utilize the other thread relational models, if loaded.
            # Check both line and file review threads for any loaded data
            [@pull_request.line_review_threads, @pull_request.file_review_threads].each do |relation|
              if relation.loaded?
                # Extract data from loaded relation and track which IDs we have
                to_column_hashes(relation).each do |hash|
                  threads << hash
                  loaded_ids << hash[:id]
                end
              else
                # Mark that we need to load remaining data from database
                load_from_database = true
              end
            end

            # Finally if we haven't loaded the entirety of the relations, load those through ActiveRecord#pluck.
            if load_from_database
              # Load only the threads we don't already have in memory
              threads.concat(
                pluck_from_relation(@pull_request.review_threads.where.not(id: loaded_ids))
              )
            end

            threads
          end

          private

          # Extract column data from loaded ActiveRecord objects in memory.
          # Converts each record's attributes to a hash containing only the required columns.
          sig { params(relation: T.untyped).returns(T::Array[HashWithIndifferentAccess]) }
          def to_column_hashes(relation)
            relation.map { _1.attributes.with_indifferent_access.slice(*THREAD_COLUMNS) }
          end

          # Execute a targeted database query to fetch only the required columns.
          # Uses pluck for efficient data transfer and converts to hash format.
          sig { params(relation: T.untyped, batch_size: Integer, max: Integer).returns(T::Array[HashWithIndifferentAccess]) }
          def pluck_from_relation(relation, batch_size: 100, max: 500)
            results = []
            relation.in_batches(of: batch_size) do |batch|
              batch.pluck(THREAD_COLUMNS).each do |values|
                results << HashWithIndifferentAccess[THREAD_COLUMNS.zip(values)]
                return results if results.size >= max
              end
            end
            results
          end

          # Parse position data from various formats into structured position objects.
          # Handles JSON strings, hashes, and already-parsed objects with validation.
          sig { params(value: T.untyped).returns(T.nilable(Positions)) }
          def parse_position(value)
            # Missing column value.
            return if value.nil? || value.blank?

            # Already parsed, reuse it.
            return value if value.is_a?(Positions)

            # If our JSON is a string, parse it.
            value = JSON.parse(value) if value.is_a?(String)
            value = value.with_indifferent_access

            # Parse and validate the given schema.
            base_commit_oid, head_commit_oid = value.values_at(:base_commit_oid, :head_commit_oid)

            # Only return valid position types, filtering out any invalid or unknown formats
            case position = Positions::Parser.parse(value, base_commit_oid:, head_commit_oid:)
            when Positions::Line, Positions::File, Positions::Multiline
              position
            end
          end
        end
      end
    end
  end
end
