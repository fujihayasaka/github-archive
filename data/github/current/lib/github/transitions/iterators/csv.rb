# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    module Iterators
      # Iterator for transitions over a CSV file.
      #
      # Checkout the class documentation of the `GitHub::Transitions::Base`
      # class for examples and more details.
      class Csv < Base
        include GitHub::Memoizer

        # Default number of rows to process at a time.
        DEFAULT_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 10, Integer
        )

        # Maximum number of rows to process at a time.
        MAX_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 100, Integer
        )

        sig do
          params(
            csv_file: String,
            csv_read_opts: T::Hash[Symbol, T.untyped],
          ).void
        end
        def initialize(csv_file:, csv_read_opts:)
          super
          @csv_file = csv_file
          @csv_read_opts = csv_read_opts

          @csv_buffer = T.let({}, T::Hash[Integer, CSV::Row])
        end

        sig { override.void }
        def validate_arguments
          unless File.exist?(@csv_file)
            raise ArgumentError.new("CSV file does not exist")
          end

          CSV.open(@csv_file, **@csv_read_opts) do |csv|
            raise ArgumentError.new("CSV file is empty") if csv.eof?
          end

          if !end_row.nil? && T.must(end_row) < start_row
            raise ArgumentError.new("end_row must be greater than or equal to start_row")
          end
        end

        sig { override.params(block: T.proc.params(items: Identifiers).void).void }
        def each_identifiers_batch(&block)
          # Stable identifier into our CSV buffer holding row data
          current_row = start_row
          yielded_batches = 0

          log "iterating with min_id=#{start_row} max_id=#{end_row} process_batch_size=#{process_batch_size}"

          # Open and seek ahead
          csv = CSV.open(@csv_file, **@csv_read_opts)
          start_row.times { csv.readline }

          current_batch = T.let([], Identifiers)
          while !csv.eof?
            # Make sure we're not at the end of the requested CSV rows
            break if !end_row.nil? && current_row >= T.must(end_row)

            row = csv.readline
            break if row.nil?

            current_batch << current_row
            @csv_buffer[current_row] = row

            if current_batch.length >= process_batch_size
              yield current_batch
              current_batch = T.let([], Identifiers)
              yielded_batches += 1
            end

            current_row += 1

            # Log every 10 * read_batch_size iterations, so we don't log
            # too much. With the default read batch size, this means
            # we log every 1000th iteration, which is every 100k rows.
            if yielded_batches % 10 == 0
              log "progress iterations=#{yielded_batches} rows=#{current_row - start_row}"
            end
          end

          # Yield the last batch
          if current_batch.length > 0
            yield current_batch
            yielded_batches += 1
          end

          log "complete total_iterations=#{yielded_batches} total_rows=#{current_row - start_row} last_id=#{current_row}"
        end

        sig { override.params(identifiers: Identifiers).returns(Items) }
        def build_items_for_batch(identifiers)
          items = T.let({}, Items)

          identifiers.each do |id|
            row = @csv_buffer.delete(id.to_i)

            # This shouldn't happen!
            next if row.nil?

            items[id.to_i] = row.to_h.symbolize_keys
          end

          items
        end

        private

        # Returns the number of rows to process at a time.
        sig { returns(Integer) }
        def process_batch_size
          value = arguments[:process_batch_size] || DEFAULT_PROCESS_BATCH_SIZE
          [value, MAX_PROCESS_BATCH_SIZE].min
        end

        # Returns the ID of the row from the `model_class` table
        # to start processing.
        sig { returns(Integer) }
        def start_row
          arguments[:start_id] || 0
        end

        # Returns the ID of the row from the `model_class` table
        # to end processing.
        sig { returns(T.nilable(Integer)) }
        def end_row
          arguments[:end_id]
        end
      end
    end
  end
end
