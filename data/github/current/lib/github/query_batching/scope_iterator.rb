# typed: true
# frozen_string_literal: true

module GitHub::QueryBatching
  # Public: Iterate over ActiveRecord scopes in batches, using a start and
  # finish ID and a max batch size.
  #
  # Given a regular ActiveRecord relation/scope, this class will try to iterate
  # over its results in batches. It does so by adding the following
  # conditions for each batch:
  #
  #   * It adds a `WHERE id BETWEEN :lower_id AND :upper_id`.
  #     This ensure each batch size is contained within limits
  #   * It shorts the query with `ORDER BY id ASC`
  #   * It adds a `LIMIT :batch_size` to make size of each batch as
  #     consistent as possible
  #
  # Each batch will be contained between a `:lower_id` and a `:upper_id`.
  # The first `:lower_id` will be the given `start` or the minimum `:id` of the
  # scoped ActiveRecord relation. The last `:upper_id` will be the given `finish`
  # or the maximum `:id` of the scoped ActiveRecord relation.
  # On each itermediate iteration the `:upper_id` will be calcualted so it takes
  # into account gaps in the sequence of IDs, keeping the size of batches
  # as consistent as possible.
  #
  # When no `start` or `finish` parameters are present, this class will fetch
  # them from the database using only on DB query.
  #
  # If during batching the class detects that the last ID in a batch is behind
  # the middle point of the range of IDs in the `BETWEEN` statement, the next
  # iteration will fast forward the `:lower_id` to the next minimum ID found
  # after the last ID. This is done to prevent iterations over empty or sparse
  # batches, reducing the total amount of queries. If the IDs are very sparse,
  # this will help adjusting batching and reduce the overall number of queries.
  # This fast forward mechanism can be disabled using the configuration object
  # yielded on initialization if a block is provided (see the examples section).
  #
  # It is possible to change the batching strategy to not bound batches between
  # an lower and upper ID and use only a lower ID as the starting point of a batch
  # plus the batch size as a limit. This is called the seek batching strategy:
  #
  #   * It adds a `WHERE id >= :lower_id` condition
  #   * It shorts the query with `ORDER BY id ASC`
  #   * It adds a `LIMIT :batch_size` to make size of each batch as
  #     consistent as possible
  #
  # This batching strategy will stop once there are no more results.
  #
  # The default strategy is always the "bounded" batching, and it is recommended
  # for tables with sharding enabled. Adding bounds to queries helps during iteration
  # over these kind of tables.
  #
  # If a table is not shared or doesn't have a lot of records, the "seek" strategy
  # can be used.
  #
  # See the examples section on how to enable the "seek" batching strategy.
  #
  # The iterator can iterate over batches directly, yielding an
  # ActiveRecord::Relation as each batch, or over single records extracted from
  # said batches.
  #
  # To avoid loading ActiveRecord models, you can use the `#pluck` method.
  # This method returns a new iterator that only yields the specified attributes.
  #
  # Requirements:
  #
  #   * The scope doesn't have an `#order` set. The batching mechanism needs to
  #   set an order over the IDs.
  #   * The scope doesn't have a `#limit` set. The batching mechanism needs to
  #     set a limit per iteration
  #   * If the scope is selecting columns with `#select`, the `:id` must be
  #     present in the list
  #
  # Notes on Sorbet types: this class uses Sorbet generics. You can annotate
  # the types that the iterator will yield to improve types support.
  # See the examples section on how to do this.
  #
  # Examples
  #
  #   # Iterate over batches
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(User.where(type: "User"), batch_size: 20)
  #   iterator.batches.each do |batch|
  #     puts batch.to_sql
  #     # => SELECT `users`.* FROM `users`
  #     # => WHERE `users`.`type` = 'User'
  #     # => WHERE `users`.`id` BETWEEN 1 AND 60
  #     # => ORDER BY `users`.`id`
  #     # => LIMIT 20
  #
  #     # batch is an ActiveRecord::Relation, so normal methods work
  #     puts batch.ids
  #     # => [1, 2, ...]
  #   end
  #
  #
  #   # Iterate over records
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(Repository.all.select(:id, :owner_id))
  #   iterator.each do |repo|
  #     puts repo.id
  #     puts repo.owner_id
  #   end
  #
  #
  #   # Iterate over attributes
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(Repository.all).pluck(:id, :owner_id)
  #   iterator.each do |attrs|
  #     puts attrs.inspect
  #     # => [1, 2]
  #   end
  #
  #
  #   # Disable fast forward during batching
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(User.where(type: "User"), batch_size: 20) do |config|
  #     config.disable_fast_forward
  #   end
  #
  #
  #   # Use "seek" batching strategy
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(User.where(type: "User"), batch_size: 20) do |config|
  #     config.use_seek_batching
  #   end
  #   iterator.batches.each do |batch|
  #     puts batch.to_sql
  #     # => SELECT `users`.* FROM `users`
  #     # => WHERE `users`.`type` = 'User'
  #     # => WHERE `users`.`id` >= 0
  #     # => ORDER BY `users`.`id`
  #     # => LIMIT 20
  #
  #     # batch is an ActiveRecord::Relation, so normal methods work
  #     puts batch.ids
  #     # => [1, 2, ...]
  #   end
  #
  #
  #   # Type annotations
  #   scope = User.all
  #   iterator = GitHub::QueryBatching::ScopeIterator[scope.class, User].new(scope)
  #   iterator.each do |user|
  #     T.reveal_type(user)
  #     # => User
  #   end
  #   iterator.batches.each do |batch|
  #     T.reveal_type(batch)
  #     # => User::PrivateRelation
  #   end
  class ScopeIterator
    extend T::Generic

    class Strategy < T::Enum
      enums do
        Bounded = new("BOUNDED")
        Seek = new("SEEK")
      end
    end

    class Config < T::Struct
      prop :strategy, Strategy
      prop :fast_forward, T::Boolean

      sig { params(other: Config).void }
      def copy(other)
        self.strategy = other.strategy
        self.fast_forward = other.fast_forward
      end

      def use_seek_batching
        self.strategy = Strategy::Seek
      end

      def use_bounded_batching
        self.strategy = Strategy::Bounded
      end

      def disable_fast_forward
        self.fast_forward = false
      end

      def enable_fast_forward
        self.fast_forward = false
      end
    end

    ScopeType = type_member { { upper: ActiveRecord::Relation } }
    RecordType = type_member

    # Default size for batches
    BATCH_SIZE = 1000

    # TODO: Allow no max id queries
    sig do
      params(
        scope: ScopeType,
        start: T.nilable(Numeric),
        finish: T.nilable(Numeric),
        batch_size: Integer,
        block: T.nilable(T.proc.params(arg0: Config).void)
      ).void
    end
    def initialize(scope, start: nil, finish: nil, batch_size: BATCH_SIZE, &block)
      @scope = scope
      @start = start
      @finish = finish
      @batch_size = batch_size

      @config = Config.new(strategy: Strategy::Bounded, fast_forward: true)
      yield @config if block_given?
    end

    sig { params(block: T.proc.params(arg0: RecordType).void).void }
    def each(&block)
      records.each(&block)
    end

    sig { returns(T::Enumerator[RecordType]) }
    def records
      Enumerator.new do |yielder|
        batches.each do |batch|
          batch.each do |record|
            yielder << record
          end
        end
      end
    end
    alias_method :rows, :records

    sig { returns(T::Enumerator[ScopeType]) }
    def batches
      validate_scope!

      strategy = config.strategy

      case strategy
      when Strategy::Bounded
        bounded_batches
      when Strategy::Seek
        seek_batches
      else
        T.absurd(strategy)
      end
    end

    sig { returns(T.nilable(String)) }
    def explain
      batches.first&.explain
    end

    sig do
      params(
        attributes: T.any(Symbol, String),
      ).returns(Pluck[ScopeType, T::Array[T.untyped]])
    end
    def pluck(*attributes)
      Pluck.new(@scope, attributes: attributes, start: @start, finish: @finish, batch_size: @batch_size) do |advanced|
        advanced.copy(config)
      end
    end

    private

    sig { returns(Config) }
    attr_reader :config

    def validate_scope!
      values = @scope.values

      if values[:select] && !select_id?(values[:select])
        msg = "Missing ID field in list of selected columns. Current selection: #{values[:select].join(", ")}"
        raise ArgumentError, msg
      end

      if values[:order]
        msg = "The query must not have an ORDER BY statement, this causes conflicts with the batching method"
        raise ArgumentError, msg
      end

      if values[:limit]
        msg = "The query must not have a LIMIT statement, this causes conflicts with the batching method"
        raise ArgumentError, msg
      end
    end

    sig { returns(T::Enumerator[ScopeType]) }
    def bounded_batches
      # NOTE: We build an enumerator that uses IteratorBuilder
      #   so we can load the start and finish values
      #   just before the batching starts
      Enumerator.new do |yielder|
        values = fetch_start_and_finish
        start = values.first || 0
        finish = values.last || 0

        builder = IteratorBuilder[ScopeType].new(start: start, finish: finish, batch_size: @batch_size, fast_forward: config.fast_forward) do |iteration|
          cursor = iteration.cursor

          batch = @scope
            .where(id: cursor.lower_id..cursor.upper_id)
            .order(:id)
            .limit(cursor.limit)

          iteration << compute_batch(batch)
        end

        builder.each do |batch|
          yielder << batch
        end
      end
    end

    sig { returns(T::Enumerator[ScopeType]) }
    def seek_batches
      builder = IteratorBuilder[ScopeType].new(start: @start || 0, batch_size: @batch_size) do |iteration|
        cursor = iteration.cursor

        seek_condition = @scope.predicate_builder[:id, cursor.lower_id, :gteq]

        batch = @scope
          .where(seek_condition)
          .order(:id)
          .limit(cursor.limit)

        iteration << compute_batch(batch)
      end

      builder.to_enum
    end

    sig { params(scope: ScopeType).returns(T.untyped) }
    def compute_batch(scope)
      scope.load
    end

    sig do
      params(
        select: T::Array[T.any(String, Symbol)]
      ).returns(T::Boolean)
    end
    def select_id?(select)
      select.include?(:id) || select.include?("id")
    end

    # In case the @start and @finish values weren't provided
    # this method will try to fetch the MIN(id) and MAX(id)
    # in one single SQL query
    sig { returns(T::Array[Numeric]) }
    def fetch_start_and_finish
      return [@start, @finish] if @start && @finish

      if @start && @finish.nil?
        max_id = @scope.pluck(max_sql).first

        return [@start, max_id]
      end

      if @finish
        min_id = @scope.pluck(min_sql).first

        return [min_id, @finish]
      end

      @scope.pluck(min_sql, max_sql).first
    end

    def min_sql
      table = arel_table
      table.coalesce(table[:id].minimum, 0)
    end

    def max_sql
      table = arel_table
      table.coalesce(table[:id].maximum, 0)
    end

    sig { returns(Arel::Table) }
    def arel_table
      T.let(T.unsafe(@scope).arel_table, Arel::Table)
    end
  end

  # Internal: The Pluck class is a ScopeIterator that instead of yielding
  # ActiveRecord models it "plucks" attributes using ActiveRecord's #pluck
  # method.
  #
  # See ScopeIterator#pluck on how to initialize this class more easily
  #
  # Examples
  #
  #   iterator = GitHub::QueryBatching::ScopeIterator.new(User.where(type: "User"), batch_size: 20).pluck(:id, "login")
  #   iterator.batches.each do |batch|
  #     puts batch.inspect
  #     # => [[1, "monalisa_avo"], ...]
  #   end
  class Pluck < ScopeIterator
    ScopeType = type_member { { upper: ActiveRecord::Relation } }
    RecordType = type_member

    sig do
      params(
        scope: ScopeType,
        attributes: T::Array[T.any(Symbol, String)],
        start: T.nilable(Numeric),
        finish: T.nilable(Numeric),
        batch_size: Numeric,
        block: T.nilable(T.proc.params(arg0: Config).void)
      ).void
    end
    def initialize(scope, attributes:, start: nil, finish: nil, batch_size: BATCH_SIZE, &block)
      @attributes = attributes

      if @attributes.first != :id && @attributes.first != "id"
        raise ArgumentError, "The first attribute of pluck MUST be the :id"
      end

      super(scope, start: start, finish: finish, batch_size: batch_size.to_i, &block)
    end

    sig { returns(T::Enumerator[T::Array[RecordType]]) }
    def batches
      T.cast(super, T::Enumerator[T::Array[RecordType]])
    end

    private

    sig { params(scope: ScopeType).returns(T.untyped) }
    def compute_batch(scope)
      scope.pluck(@attributes)
    end
  end
end
