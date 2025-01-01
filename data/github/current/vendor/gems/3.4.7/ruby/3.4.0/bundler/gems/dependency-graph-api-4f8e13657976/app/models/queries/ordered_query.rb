# An ordered query that support limits/offsets using a WHERE clause that
# uses the cursor values for the field being ordered by.
#
# This gets pagination working correctly when an ORDER BY is being used.
#
# Heavily inspired by the github/github support for this:
#
#   - lib/platform/connection_wrappers/relation.rb
#   - lib/platform/connection_wrappers/relation/condition.rb
#   - lib/platform/connection_wrappers/relation/ordering.rb
module Queries
  module OrderedQuery
    include RelayQuery

    COMPARATORS = {
      before: {
        asc: "<",
        desc: ">"
      },
      after: {
        asc: ">",
        desc: "<"
      }
    }.freeze

    def add_order_by_conditions(*args)
      raise NotImplementedError
    end

    def order_by_direction
      raise NotImplementedError
    end

    def order_by_condition
      raise NotImplementedError
    end

    def id_column
      raise NotImplementedError
    end

    def first(n)
      @first = n
      self
    end

    def last(n)
      @last = n
      self
    end

    # Get the inverse scope for the configured before/after values
    def inverse_scope
      @inverse_scope ||= apply_cursors(scope, inverse: true)
    end

    # Apply limits to the scope using the first and last arguments
    def apply_limits(scope)
      if @first.nil? && @last.nil?
        @first = limit
      end

      if @first
        scope = scope.limit(@first + 1).to_a
      elsif @last
        scope = scope.reverse_order.limit(@last + 1).to_a.reverse
      end

      if @first
        @has_next_page = scope.count > @first
        scope = scope.first(@first)
      end

      if @last
        @has_previous_page = scope.count > @last
        scope = scope.last(@last)
      end

      scope
    end

    # Apply ordering conditions from the before/after cursor to the scope
    def apply_cursors(scope, inverse: false)
      if after?
        cursor_direction = inverse ? :before : :after
        scope = order_conditions(scope, @after, cursor_direction, equal_to: inverse)
      end

      if before?
        cursor_direction = inverse ? :after : :before
        scope = order_conditions(scope, @before, cursor_direction, equal_to: inverse)
      end

      scope = scope.reverse_order if inverse

      scope
    end

    # Add ordering conditions for the values and direction of a cursor
    def order_conditions(scope, cursor_values, cursor_direction, equal_to: false)
      id, order_by_value = cursor_values

      comparator = COMPARATORS.fetch(cursor_direction).fetch(order_by_direction)
      conditions = "#{id_column} #{comparator} ?"
      values = [id]

      if order_by_condition
        order_by_comparator = comparator
        order_by_comparator += "=" if equal_to
        conditions = "(#{order_by_condition} #{order_by_comparator} ?) OR (#{order_by_condition} = ? AND #{conditions})"
        values.unshift(order_by_value, order_by_value)
      end

      add_order_by_conditions(scope, conditions, values)
    end

    def has_previous?
      # Load results first
      results

      unless defined?(@has_previous_page)
        @has_previous_page = after? ? inverse_scope.limit(1).present? : false
      end
      @has_previous_page
    end

    def has_next?
      # Load results first
      results

      unless defined?(@has_next_page)
        @has_next_page = before? ? inverse_scope.limit(1).present? : false
      end
      @has_next_page
    end
  end
end
