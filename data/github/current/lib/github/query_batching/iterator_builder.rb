# typed: true
# frozen_string_literal: true

module GitHub::QueryBatching
  # Public: This class helps builds batch iterators.
  # It manages how to calculate batch limits, like lower and upper ids,
  # how to yield results and delegates the logic of calculating a batch
  # to clients of the class.
  #
  # The class is based on the following concepts:
  #   * A batch is bounded to a lower id
  #   * A batch can be bounded to an upper id
  #   * A batch is limited to a certain size
  #
  # When no finish is provided, this class will build iterators
  # that will calculate the lower ID bound for each iteration and it will
  # stop once a batch doesn't have any result.
  #
  # When a start and a finish are provided, this class will build
  # iterators that will te each set of ids for each iteration,
  # and it will stop once the ids are out of bounds.
  #
  # The logic to fetch a batch of results given the provided IDs is up to the
  # client building the iterator. This helps clients to focus on how to get a
  # batch and delegates all the logic around boundaries and iteration
  # management to this builder.
  #
  # The logic on how to fetch a batch is defined on initialization with a block.
  # This block will receive:
  #
  # itertion - A Iteration object that holds a reference to the current Cursor,
  #            the object that holds the information of the current batch
  #            `:lower_id`, `:upper_id` and `:limit`. The iteration object acts
  #            as a Yielder, that is, it `#yields` the results of each iteration.
  #            It can also be used to stop the iteration early with the `#stop`
  #            method.
  #
  # The builder will use the results passed to the Iteration object to calculate the
  # next boundaries. It will try to extract the last ID from the results and move from
  # there.
  #
  # The Iteration object accepts results as objects that respond to:
  #
  # - #size: to  the current batch size
  # - #last: to obtain the last item in the batch
  #
  # That is, it accepts Arrays or Array like objects, like an ActiveRecord relation.
  #
  # The last item of the results can be:
  #
  # - An array of attributes, in which case the first element is expected to be the ID
  # - A single number, the ID
  # - An object that responds to #id
  #
  # If the items of a result object don't match any of the previous forms, it is possible
  # to assign the #last_id to the iteration manually with `iteration.last_id = value`
  #
  # When batching with a start and a finish, the builder will try to see if there are gaps
  # on the batches and "fast forward" if it finds a big gap. The logic to fast forward
  # is as follows:
  #
  # If the last batch is smaller than the expected :batch_size, and the last ID is lower
  # than the middle point between the last batch :lower_id and :upper_id boundaries, we
  # assume that the next batch could be lower in results or empty. In this case the next
  # batch boundaries will be the next ID to the last ID (last_id + 1) as the :lower_id
  # and the :finish ID as the :upper_id, with a limit of 2 to limit the result size.
  # The idea behind this is to calculate the next minimum ID on the sequence, moving
  # the whole batching forward, with a controlled set of IDs.
  #
  # Notes on Sorbet types: this class uses Sorbet generics. You can annotate
  # the types that the iterator will yield to improve types support.
  # See the examples section on how to do this.
  #
  # Examples
  #
  #   # Building an iterator with start and a finish
  #   iterator = GitHub::QueryBatching::IteratorBuilder.new(start: 1, finish: 100, batch_size: 10) do |iteration|
  #     results = ApplicationRecord::Domain::User.connection.select_rows(Arel.sql(<<-SQL, **iteration.cursor.arel_bindings))
  #       SELECT users.id, users.login
  #       WHERE users.type = 'Organization'
  #       WHERE users.id BETWEEN :lower_id AND :upper_id
  #       ORDER BY users.id
  #       LIMIT :limit
  #     SQL
  #
  #     iteration << results
  #   end
  #
  #   iterator.to_enum.each do |batch|
  #     puts batch.inspect
  #     # => [[1, "monalisa"], ...]
  #   end
  #
  #
  #   # Building an iterator over Arel queries and with type annotations
  #   iterator = GitHub::QueryBatching::IteratorBuilder[T::Array[[Integer, String]]].new(start: 1, finish: 100, batch_size: 10) do |iteration|
  #     results = ApplicationRecord::Domain::User.connection.select_rows(Arel.sql(<<-SQL, **iteration.cursor.arel_bindings))
  #       SELECT users.id, users.login
  #       WHERE users.type = 'Organization'
  #       WHERE users.id BETWEEN :lower_id AND :upper_id
  #       ORDER BY users.id
  #       LIMIT :limit
  #     SQL
  #
  #     iteration << results
  #   end
  #
  #   iterator.to_enum.each do |batch|
  #     puts batch.inspect
  #     # => [[1, "monalisa"], ...]
  #     T.reveal_type(batch)
  #     # => T::Array[[Integer, String]]
  #   end
  #
  #
  #   # Building an iterator with start and a finish and no fast forward mechanism
  #   iterator = GitHub::QueryBatching::IteratorBuilder.new(start: 1, finish: 100, batch_size: 10, fast_forward: false) do |iteration|
  #     results = ApplicationRecord::Domain::User.connection.select_rows(Arel.sql(<<-SQL, **iteration.cursor.arel_bindings))
  #       SELECT users.id, users.login
  #       WHERE users.type = 'Organization'
  #       WHERE users.id BETWEEN :lower_id AND :upper_id
  #       ORDER BY users.id
  #       LIMIT :limit
  #     SQL
  #
  #     iteration << results
  #   end
  #
  #
  #   # Building an iterator without upper boundary
  #   iterator = GitHub::QueryBatching::IteratorBuilder.new(batch_size: 10) do |iteration|
  #     results = ApplicationRecord::Domain::User.connection.select_rows(Arel.sql(<<-SQL, **iteration.cursor.arel_bindings))
  #       SELECT users.id, users.login
  #       WHERE users.type = 'Organization'
  #       WHERE users.id >= :lower_id
  #       ORDER BY users.id
  #       LIMIT :limit
  #     SQL
  #
  #     iteration << results
  #   end
  #
  #   iterator.to_enum.each do |batch|
  #     puts batch.inspect
  #     # => [[1, "monalisa"], ...]
  #   end
  class IteratorBuilder
    class Cursor < T::Struct
      extend T::Sig

      prop :lower_id, Numeric
      prop :upper_id, Numeric
      prop :limit, Integer

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def arel_bindings
        {
          lower_id: lower_id,
          upper_id: upper_id,
          limit: Arel.sql(limit.to_s),
        }
      end
    end

    class Iteration
      extend T::Sig

      sig { params(batch_size: Integer).returns(Integer) }
      attr_writer :batch_size

      sig { params(last_id: T.nilable(Numeric)).returns(T.nilable(Numeric)) }
      attr_writer :last_id

      sig { returns(Cursor) }
      attr_reader :cursor

      sig { params(cursor: Cursor, yielder: Enumerator::Yielder).void }
      def initialize(cursor, yielder)
        @cursor = cursor
        @yielder = yielder
        @batch = []
      end

      sig { params(batch: T.untyped).void }
      def yield(batch)
        @batch = batch

        @yielder << @batch unless batch_size.zero?
      end
      alias_method :<<, :yield

      sig { returns(Integer) }
      def batch_size
        @batch_size ||= @batch.size
      end

      sig { returns(T.nilable(Numeric)) }
      def last_id
        return @last_id if defined?(@last_id)

        @last_id = fetch_last_id
      end

      sig { returns(T.nilable(Numeric)) }
      def next_id
        return nil if last_id.nil?

        T.must(last_id) + 1
      end

      sig { void }
      def stop
        @stop = true
      end

      sig { returns(T::Boolean) }
      def stop?
        !!@stop
      end

      sig { returns(T::Boolean) }
      def fast_forward?
        return true if last_id.nil?

        middle_point = cursor.lower_id + (cursor.upper_id - cursor.lower_id) * 0.5

        batch_size < cursor.limit && T.must(last_id) < middle_point
      end

      private

      sig { returns(T.nilable(Numeric)) }
      def fetch_last_id
        last = @batch.last
        return unless last

        case last
        when Array
          # This assumes this is an array of attributes where the ID is the first one
          last.first
        when Numeric
          last
        when ->(record) { record.respond_to?(:id) }
          last.id
        else
          nil
        end
      end
    end

    extend T::Sig
    extend T::Generic

    BatchType = type_member

    BATCH_SIZE = 1000
    BATCH_ID_CORRECTION = 3

    sig do
      params(
        start: Numeric,
        finish: T.nilable(Numeric),
        batch_size: Integer,
        fast_forward: T::Boolean,
        block: T.proc
          .params(arg0: Iteration)
          .void,
      ).void
    end
    def initialize(start: 0, finish: nil, batch_size: BATCH_SIZE, fast_forward: true, &block)
      @start = start
      @finish = finish
      @batch_size = batch_size
      @fetcher = block
      @fast_forward_enabled = fast_forward
    end

    sig { params(block: T.proc.params(arg0: BatchType).void).void }
    def each(&block)
      to_enum.each(&block)
    end

    sig { returns(T::Enumerator[BatchType]) }
    def to_enum
      Enumerator.new do |yielder|
        next if @finish && [@start, @finish].all?(&:zero?)

        cursor = build_cursor(lower_id: @start)

        loop do
          iteration = Iteration.new(cursor, yielder)

          @fetcher.call(iteration)

          break if iteration.stop?
          break if @finish.nil? && iteration.batch_size.zero?

          lower_id = iteration.next_id || cursor.upper_id + 1

          break if @finish && lower_id > @finish

          cursor = if @fast_forward_enabled && @finish && iteration.fast_forward?
            build_cursor(lower_id: lower_id, upper_id: @finish, limit: 2)
          else
            build_cursor(lower_id: lower_id)
          end
        end
      end
    end
    alias_method :batches, :to_enum

    private

    sig { params(lower_id: Numeric, upper_id: T.nilable(Numeric), limit: T.nilable(Integer)).returns(Cursor) }
    def build_cursor(lower_id:, upper_id: nil, limit: nil)
      Cursor.new(lower_id: lower_id, upper_id: upper_id || calculate_upper_id(lower_id), limit: limit || @batch_size)
    end

    sig { params(lower_id: Numeric).returns(Numeric) }
    def calculate_upper_id(lower_id)
      upper_id = lower_id + @batch_size * BATCH_ID_CORRECTION
      return @finish if @finish && upper_id > @finish

      upper_id
    end
  end
end
