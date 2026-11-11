# typed: strict
# frozen_string_literal: true

module GitHub
  module Transitions
    module Iterators
      # Iterator for transitions over any size of MySQL database tables.
      #
      # Checkout the class documentation of the `GitHub::Transitions::Base`
      # class for examples and more details.
      class DatabaseTable < Base

        # Default number of workers to use for parallelization. Intends to
        # be a safe default for most transitions.
        DEFAULT_WORKER_COUNT = T.let(4, Integer)

        # Maximum number of workers to use for parallelization. Intends to
        # match the number of unicorn workers, configured via
        # `GH_UNICORN_WORKER_COUNT`.
        MAX_WORKER_COUNT = T.let(16, Integer)

        # Default number of rows to read at a time.
        DEFAULT_READ_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 100, Integer
        )

        # Maximum number of rows to read at a time. This is limited
        # to a maximum of 16KB per batch. That limit is coming form
        # Divvy's limitation to pass more from the main to the worker
        # processes. We are passing `Integer` values as identifiers,
        # which are 8 bytes each. So we can pass 2048 identifiers.
        # We leave some buffer and limit it to 1800.
        MAX_READ_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 10000 : 1800, Integer
        )

        # Default number of rows to process at a time.
        DEFAULT_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 10, Integer
        )

        # Maximum number of rows to process at a time.
        MAX_PROCESS_BATCH_SIZE = T.let(
          GitHub.enterprise? ? 1000 : 100, Integer
        )

        # ApplicationRecord subclass used for reading. It's defining the
        # connection and table the transition iterates over. This is usally
        # a subclass of a domain class defined inline of the transition class.
        #
        # See class description above for example.
        #
        sig { returns(T.class_of(ApplicationRecord::Base)) }
        attr_accessor :model_class

        # A string containing the SQL conditions (`WHERE` clause) to be used
        # for selecting the rows on the table defined by `model_class`.
        sig { returns(String) }
        attr_accessor :conditions

        # List of column names to be selected from the table, next to the `id`.
        sig { returns(T::Array[Symbol]) }
        attr_accessor :columns

        sig do
          params(
            model_class: T.class_of(ApplicationRecord::Base),
            conditions: String,
            columns: T::Array[Symbol]
          ).void
        end
        def initialize(model_class:, conditions: "", columns: [])
          super

          @model_class = model_class
          @conditions = conditions
          @columns = columns
        end

        sig { override.void }
        def validate_arguments
          self.conditions.freeze
          self.columns.freeze

          if self.model_class.nil?
            raise ArgumentError.new("no model class defined")
          end

          if self.model_class > ::ApplicationRecord::Base
            raise ArgumentError.new("model class has to inherit from `ApplicationRecord::Base`")
          end

          if self.model_class.connection_class?
            raise ArgumentError.new("model class cannot be a connection class")
          end

          if self.model_class.abstract_class?
            raise ArgumentError.new("model class cannot be an abstract class")
          end

          self.model_class.unscoped.annotate("cross-shard-query-exempted").limit(1).pluck(:id)
        end

        sig { override.void }
        def prepare_iteration
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        sig { override.void }
        def prepare_worker
          ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
        end

        sig do
          override.params(
            block: T.proc.params(identifiers: Identifiers).void
          ).void
        end
        def each_identifiers_batch(&block)
          min_id = load_min_id
          max_id = load_max_id
          iteration_count = 0
          rows_count = 0

          log "iterating with min_id=#{min_id} max_id=#{max_id} read_batch_size=#{read_batch_size} process_batch_size=#{process_batch_size}"

          last_id = min_id - 1
          while last_id < max_id do
            ids = load_ids(last_id, max_id)
            ids.each_slice(process_batch_size) do |ids_slice|
              ActiveRecord::Base.connected_to(role: :reading) do
                yield ids_slice
              end
            end

            last_id = if ids.last && ids.size == read_batch_size
              T.must(ids.last)
            else
              [last_id + (read_batch_size * 5), max_id].min
            end

            iteration_count += 1
            rows_count += ids.size

            # Log every 10 * read_batch_size iterations, so we don't log
            # too much. With the default read batch size, this means
            # we log every 1000th iteration, which is every 100k rows.
            if iteration_count % (read_batch_size * 10) == 0
              log "progress iterations=#{iteration_count} rows=#{rows_count} last_id=#{last_id}"
            end
          end

          log "complete total_iterations=#{iteration_count} total_rows=#{rows_count} last_id=#{last_id}"
        end

        sig { override.params(identifiers: Identifiers).returns(Items) }
        def build_items_for_batch(identifiers)
          items = Hash[identifiers.map { |i| [i, {}] }]

          if columns.any?
            add_columns(items)
          end

          items.each(&:freeze)
          items.freeze
        end

        sig { override.returns(Integer) }
        def worker_count
          if GitHub.enterprise?
            ghes_worker_count
          else
            value = arguments[:workers] || DEFAULT_WORKER_COUNT
            [value, MAX_WORKER_COUNT].min
          end
        end

        # This method determines the worker count for currently running transition in GHES.
        # It reads a JSON file containing a list of Migration IDs to exclude from concurrent processing.
        # The path to this JSON file is specified by the environment variable `GHES_TRANSITION_CONCURRENCY_EXCLUDE_LIST`.
        # If the current Migration ID is in the exclude list, the worker count is set to 1.
        # If the environment variable is not set or the file is not readable,
        #   the method returns the default worker count specified by the environment variable `GHES_TRANSITION_WORKER_COUNT`,
        #   defaulting to 1 if not set.
        #
        # This method uses puts instead of logger to ensure the message is printed on stdout in GHES, along side other ActiveRecord messages (ActiveRecord uses puts for logging).
        sig { returns(Integer) }
        def ghes_worker_count
          exclude_list_path = ENV["GHES_TRANSITION_CONCURRENCY_EXCLUDE_LIST"]
          default_ghes_worker_count = ENV.fetch("GHES_TRANSITION_WORKER_COUNT", 1).to_i

          current_migration_id = transition&.migration_id
          if current_migration_id.nil?
            puts "Migration ID cannot be determined. Using the default worker count."
            return default_ghes_worker_count
          end

          if exclude_list_path.nil? || exclude_list_path.empty?
            puts "The GHES_TRANSITION_CONCURRENCY_EXCLUDE_LIST file is not set. Using the default worker count."
            return default_ghes_worker_count
          end

          if File.open(exclude_list_path).grep(/#{current_migration_id}/).any?
            puts "The current migration version #{current_migration_id} is in the GHES_TRANSITION_CONCURRENCY_EXCLUDE_LIST. Using a single worker."
            1
          else
            default_ghes_worker_count
          end
        end

        private

        sig { returns(Integer) }
        def load_min_id
          start_id || ActiveRecord::Base.connected_to(role: :reading) do
            self.model_class.minimum(:id) || 0
          end
        end

        sig { returns(Integer) }
        def load_max_id
          end_id || ActiveRecord::Base.connected_to(role: :reading) do
            self.model_class.maximum(:id) || 0
          end
        end

        sig do
          params(
            last_id: Integer,
            max_id: Integer
          ).returns(T::Array[Integer])
        end
        def load_ids(last_id, max_id)
          # To move through id range gaps more quickly, we look at a maximum
          # of 5 times the read batch size at a time to find the next batch.
          max_next_batch_id = last_id + read_batch_size * 5

          scope = self.model_class.
            where("id > ?", last_id).
            where("id <= ?", max_id).
            where("id <= ?", max_next_batch_id).
            order(id: :asc).
            limit(read_batch_size)
          scope = scope.where(conditions) if conditions.present?

          ActiveRecord::Base.connected_to(role: :reading) do
            scope.pluck(:id)
          end
        end

        sig { params(items: Items).void }
        def add_columns(items)
          all_columns = ([:id] + self.columns)
          ids = items.keys

          column_values = self.model_class.where(id: ids).pluck(all_columns)
          column_values_by_id = column_values.index_by(&:first)

          items.each do |id, hash|
            column_values_for_id = column_values_by_id[id]
            next unless column_values_for_id

            column_values_for_id.each_with_index do |value, index|
              column = T.must(all_columns[index])
              next if column == :id

              hash[column] = value
            end
          end
        end

        # Returns the number of rows to read at a time.
        sig { returns(Integer) }
        def read_batch_size
          value = arguments[:read_batch_size] || DEFAULT_READ_BATCH_SIZE
          [value, MAX_READ_BATCH_SIZE].min
        end

        # Returns the number of rows to process at a time.
        sig { returns(Integer) }
        def process_batch_size
          value = arguments[:process_batch_size] || DEFAULT_PROCESS_BATCH_SIZE
          [value, MAX_PROCESS_BATCH_SIZE].min
        end

        # Returns the ID of the row from the `model_class` table
        # to start processing.
        sig { returns(T.nilable(Integer)) }
        def start_id
          arguments[:start_id]
        end

        # Returns the ID of the row from the `model_class` table
        # to end processing.
        sig { returns(T.nilable(Integer)) }
        def end_id
          arguments[:end_id]
        end

        # Returns the table name of the `model_class`.
        sig { returns(String) }
        def table_name
          self.model_class.table_name
        end
      end
    end
  end
end
