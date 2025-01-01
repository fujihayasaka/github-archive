# typed: true
# frozen_string_literal: true

# The GitHub::BatchedScope can be included in any ActiveRecord model to add the batched_scope
# method to help with batching queries that have a long list of ids as an attribute.
#
# Note: Ordering the results is only supported when using paginate.
#
# Usage example:
#
#   User.suspended.batched_scope(:id, values: org.member_ids).count
#
#   User.suspended.batched_scope(:id, values: org.member_ids).to_a
#
#   User.batched_scope(:id, values: business.member_ids) { |scope|
#     scope.disabled_by_scim.where.not(login: emu_admin_login)
#   }.pluck(:id)
#
#   User.batched_scope(:id, values: business.organization_member_ids) { |scope|
#     scope.two_factor_disabled
#   }.any?
#
#   User.suspended.batched_scope(:id, values: org.member_ids).order(:login).paginate(page: 1)
#
module GitHub::BatchedScope
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  BATCH_SIZE = 1_000

  module ClassMethods
    extend T::Helpers
    extend T::Generic

    requires_ancestor { T.class_of(ActiveRecord::Base) }
    has_attached_class! { { upper: ActiveRecord::Base } }

    # Public: Create a new batched scope
    #
    # param       - Symbol for setting the id attribute used when the batched_scope_id_query
    #               is called. This is the attribute that is used for fetching the records using
    #               the supplied ids (in most cases :id or :user_id).
    # values      - A list of ids or other values to be used for batching in a IN(?) query.
    # batch_size  - (optional) Integer representing the number of ids used for each batch. When
    #               left empty a default value of 1000 is used.
    # context     - (optional) Additional data to be provided for any Failbot reports.
    # block       - (optional) The block is executed for each batch, allowing further queries on
    #               the result of each batch,
    #
    # Returns a BatchedScopeQuery
    sig do
      params(
        param: Symbol,
        values: T::Enumerable[T.untyped],
        batch_size: T.nilable(Integer),
        context: T.untyped,
        block: T.nilable(T.proc.params(arg0: T.untyped).returns(T.untyped)),
      ).returns(BatchedScopeQuery[T.attached_class])
    end
    def batched_scope(param, values:, batch_size: nil, context: nil, &block)
      ::GitHub::BatchedScope::BatchedScopeQuery.new(klass: self, values: values, id_param: param, id_scope: self.current_scope, batch_scope: block, batch_size: batch_size, context: context)
    end
  end
  mixes_in_class_methods(ClassMethods)

  # Public: Perform a batched operation
  #
  # values      - A list of ids or other values to be used for batching in a IN(?) query.
  # batch_size  - (optional) Integer representing the number of ids used for each batch. When
  #               left empty a default value of 1000 is used.
  # block       - The block is executed for each batch, the results are returned as a flat_map.
  #
  # Returns an Array of the results of the block
  sig do
    type_parameters(:V, :R)
      .params(
        values: T::Array[T.type_parameter(:V)],
        batch_size: T.nilable(Integer),
        context: T.untyped,
        block: T.proc.params(arg0: T::Array[T.type_parameter(:V)]).returns(T.any(
          T.type_parameter(:R),
          T::Array[T.type_parameter(:R)],
        ))
      )
      .returns(T::Array[T.type_parameter(:R)])
  end
  def self.batched(values:, batch_size: nil, context: nil, &block)
    values.in_groups_of(batch_size || BATCH_SIZE, false).flat_map do |slice|
      yield slice
    end
  end

  class LargeBatchSize < StandardError; end

  class BatchedScopeQuery
    extend T::Generic

    Model = type_member { { upper: ActiveRecord::Base } }

    def initialize(klass:, values:, id_param:, id_scope: nil, base_scope: nil, batch_scope: nil, batch_size: nil, context: nil, order: nil)
      @klass = klass
      @values = values
      @id_param = id_param
      @id_scope = id_scope
      @base_scope = base_scope || proc { |values| batched_scope_in_query(values) }
      @batch_scope = [batch_scope].compact
      @batch_size = batch_size || BATCH_SIZE
      @context = context || {}
      @order = order
    end

    def batched_scope_in_query(values)
      (@id_scope || @klass).where({ @id_param => values })
    end

    def execute
      values = @values.to_a
      begin
        raise ::GitHub::BatchedScope::LargeBatchSize.new if values.size >= @batch_size * 100
      rescue ::GitHub::BatchedScope::LargeBatchSize => error
        # The exception is logged silently to GitHub::Logger, but execution still continues
        GitHub::Logger.log_exception({
          object_class: @klass.name,
          values_size: values.size,
          batch_size: @batch_size
        }.merge(@context), error)
      end
      ::GitHub::BatchedScope.batched(values: values, batch_size: @batch_size) do |slice|
        slice_scope = @base_scope.call(slice)
        slice_scope = call_batch_scope(slice_scope)
        res = yield slice_scope
        res
      end
    end

    # Public: Sums up the number of results of each batch.
    # Returns a Number
    sig { returns(Integer) }
    def count
      execute { |scope| scope.count }.sum
    end
    alias :size :count

    # Public: Plucks attributes from each result.
    # Returns an Array of attributes
    sig { params(args: T.untyped).returns(T::Array[T.untyped]) }
    def pluck(*args)
      execute { |scope| scope.pluck(*args) }
    end

    # Public: Returns each matched record.
    # Returns an Array of ActiveRecord objects
    sig { returns(T::Array[Model]) }
    def to_a
      execute { |scope| scope.to_a }
    end
    alias :all :to_a
    alias :to_ary :to_a

    # Public: Enables ordering for paginated queries
    # Returns self
    sig { params(order: T.untyped).returns(T.self_type) }
    def order(order)
      @order = order
      self
    end

    # Public: Returns an ordered and paginated list of the matched records.
    # Returns an Array of ActiveRecord objects
    sig { params(page: Integer, per_page: Integer, order: T.untyped).returns(WillPaginate::Collection) }
    def paginate(page:, per_page: 30, order: nil)
      values = @values.to_a
      begin
        raise ::GitHub::BatchedScope::LargeBatchSize.new if values.size >= @batch_size * 100
      rescue ::GitHub::BatchedScope::LargeBatchSize => e
        Failbot.report(e, {
          class: @klass.name,
          values_size: values.size,
          batch_size: @batch_size
        }.merge(@context))
      end
      last_results = T.let([], T::Array[T.untyped])
      res = T.let([], T::Array[T.untyped])
      limit = page * per_page
      order ||= @order
      ::GitHub::BatchedScope.batched(values: values, batch_size: @batch_size) do |slice|
        slice_scope = @base_scope.call(slice + last_results)
        slice_scope = call_batch_scope(slice_scope)
        res = slice_scope.order(order).limit(limit).to_a
        last_results = res.pluck(:id)
        res
      end
      WillPaginate::Collection.create(page, per_page) do |pager|
        pager.replace(res.slice((page - 1) * per_page, per_page) || [])
        pager.total_entries = @batch_scope.any? ? count : values.size
      end
    end

    # Public: Tests if there is any result to any of the batch queries.
    # Returns Boolean
    sig { returns(T::Boolean) }
    def any?
      execute { |scope| return true if scope.any?  }
      false
    end
    alias :exists? :any?

    # Public: checks for empty results
    # Returns Boolean
    sig { returns(T::Boolean) }
    def empty?
      !any?
    end
    alias :none? :empty?

    # Public: Supports testing if a value is included in the batched scope.
    # Returns Boolean
    sig { params(value: T.untyped).returns(T::Boolean) }
    def include?(value)
      execute { |scope| return true if scope.include?(value) }
      false
    end

    # Public: Supports mapping over the batched scope.
    # Returns an Array of mapped values
    sig do
      type_parameters(:R)
        .params(block: T.proc.params(arg0: Model).returns(T.type_parameter(:R)))
        .returns(T::Array[T.type_parameter(:R)])
    end
    def map(&block)
      execute { |scope| scope.map(&block) }
    end

    # Public: Supports filtering with where over the batched scope.
    # Returns a filtered Array of values
    sig { params(args: T.untyped).returns(T::Array[Model]) }
    def where(*args)
      execute { |scope| scope.where(*args) }
    end

    # Public: Returns the first result of the batched scope.
    # Returns an ActiveRecord object
    sig { returns(T.nilable(Model)) }
    def first
      to_a.first
    end

    # Public: Returns added results of batch scopes
    # Returns an array of ActiveRecord objects
    sig do
      type_parameters(:O)
        .params(other: T.any(
          BatchedScopeQuery[T.all(T.type_parameter(:O), ActiveRecord::Base)],
          T::Enumerable[T.type_parameter(:O)])
        )
        .returns(T::Array[T.any(Model, T.type_parameter(:O))])
    end
    def +(other)
      to_a + other.to_a
    end

    # Public: Iterates over the batched scope.
    # Returns an iterator
    sig { params(block: T.nilable(T.proc.params(arg0: Model).void)).returns(T::Enumerable[Model]) }
    def each(&block)
      if block.present?
        execute { |scope| scope.each(&block) }
      else
        execute { |scope| scope.each }
      end
    end

    # Public: Add a includes call to the scope
    # Returns self
    sig { params(args: T.untyped).returns(T.self_type) }
    def includes(*args)
      @batch_scope.push proc { |scope| scope.includes(*args) }
      self
    end

    private

    def call_batch_scope(scope)
      @batch_scope.each { |s| scope = s.call(scope) }
      scope
    end
  end
end
