# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    class KVCleaner
      extend T::Sig

      class Result < T::Struct
        extend T::Sig

        const :status, Symbol
        const :batch_count, Integer
        const :deleted_key_count, Integer
        const :job_duration, Integer

        sig { returns(Integer) }
        attr_reader :deleted_key_count

        sig { returns(Symbol) }
        attr_reader :status

        sig { returns(T::Boolean) }
        def completed?
          @status == :completed
        end

        sig { params(other: Object).returns(T::Boolean) }
        def ==(other)
          other.is_a?(self.class) &&
            status == other.status &&
            batch_count == other.batch_count &&
            deleted_key_count == other.deleted_key_count &&
            job_duration == other.job_duration
        end
      end

      sig { returns(T.class_of(ApplicationRecord::Base)) }
      attr_reader :model_class

      sig { returns(Integer) }
      attr_reader :batch_size

      # initialize :: ApplicationRecord::Base, Integer -> nil
      #
      # Initialize a new KVCleaner instance.
      #
      # model_class:  - The model class for the target kv store
      # batch_size:   - The batch size to use for processing expired keys
      #
      # Returns nothing.
      sig { params(model_class: T.class_of(ApplicationRecord::Base), batch_size: Integer).void }
      def initialize(model_class:, batch_size: 100)
        @model_class = model_class
        @batch_size = batch_size
      end

      # cleanup_expired_keys :: Duration -> KVCleaner::Result
      #
      # Cleans up expired keys in a loop, starting from most recently
      # expired keys working backward to oldest. The specified duration
      # is used to determine the maximum execution time for the loop.
      #
      # Returns data about the execution of the cleanup.
      sig { params(max_duration: ActiveSupport::Duration).returns(Result) }
      def cleanup_expired_keys(max_duration: 5.minutes)
        batch_count = 0
        deleted_key_count = 0
        job_duration = 0
        started_at = Time.current
        end_at = Time.current + max_duration
        status = T.let(:completed, Symbol)
        tags = ["table:#{@model_class.table_name}"]
        min_expiration = T.let(nil, T.nilable(Time))
        max_expiration = T.let(Time.now, T.nilable(Time))
        key_columns = Array(@model_class.primary_key)
        keys_to_delete = T.let([], T::Array[T.untyped])

        GitHub.dogstats.time("kv.cleaner.duration", tags: tags) do
          loop do
            # first read a batch of items ordered by expires_at desc
            ActiveRecord::Base.connected_to(role: :writing) do
              keys_to_delete = @model_class
                .select(["expires_at", *key_columns])
                .where("expires_at <= ?", max_expiration)
                .order(expires_at: :desc)
                .limit(@batch_size)
            end

            min_expiration = keys_to_delete.last&.expires_at
            break if min_expiration.blank?

            # use the primary key columns to delete the rows. this enables support
            # for various forms of primary keys, such as :id or a composite key
            # [:partition_id, :key] for sharded stores. we manually build the values
            # list so we generate an IN clause against tuples rather than a bunch of
            # OR statements which is what AR tries to do when using something like:
            #
            #   @model_class.where(key_columns => keys_to_delete.map { |r| r.values_at(key_columns) })
            #
            in_columns = key_columns.map { |col| @model_class.connection.quote_column_name(col) }
            in_values = keys_to_delete.map do |row|
              "(#{row.values_at(key_columns).map { |val| @model_class.connection.quote(val) }.join(", ")})"
            end

            # delete by the primary key, but additionally filter the expiration time
            # to ensure the value hasn't changed since it was read above.
            deleted_count = T.let(0, Integer)
            @model_class.throttle_writes_with_retry do
              deleted_count = @model_class
                .where("(#{in_columns.join(", ")}) IN (#{in_values.join(", ")})")
                .where("`expires_at` >= ?", min_expiration)
                .where("`expires_at` <= ?", max_expiration)
                .delete_all
            end

            deleted_key_count += deleted_count
            GitHub.dogstats.count("kv.cleaner.keys.count", deleted_count, tags: tags)

            batch_count += 1
            GitHub.dogstats.count("kv.cleaner.batches.count", 1, tags: tags)

            # make sure we respect, to an approximation, the maximum execution time
            if Time.current >= end_at
              status = :timed_out
              break
            end

            max_expiration = min_expiration
          end
        end

        job_duration = (Time.current - started_at).to_i

        # return whether or not we expired in addition to how batch and key metrics
        Result.new(status:, batch_count:, deleted_key_count:, job_duration:)
      end
    end
  end
end
