# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Relation < ConnectionWrappers::Base
      def initialize(items, **kwargs)
        if kwargs[:first].nil? && kwargs[:last].nil?
          kwargs[:first] = kwargs[:max_page_size].present? ? kwargs[:max_page_size] : Schema::DEFAULT_MAX_PER_PAGE
        end

        @disable_max_page_size_validation = kwargs.delete(:disable_max_page_size_validation) || false
        super(
          items,
          **kwargs
        )
        if !items.nil?
          @items, @orderings = Ordering.from_relation(items)
        end
      end

      def set_security_violation_behaviour(behavior)
        validate_security_violation_behavior!(behavior)
        @security_violation_behaviour = behavior
      end

      def cursor_for(item)
        ::Promise.resolve(item).then do |item_sync|
          fetch_ordering(item_sync).then { |result| encode_cursor(result) }
        end
      end

      def edge_nodes(unscoped: false)
        @edge_nodes ||= begin
          ::Promise.all(results.map do |id|
            relation_class = unscoped ? @items.klass.unscoped : @items.klass
            Loaders::ActiveRecord.load(
              relation_class,
              id,
              security_violation_behaviour: (@security_violation_behaviour || :raise),
              shard_key: shard_key(relation_class)
            )
          end)
        end
      end

      def page_info
        @page_info ||= begin
          page_info_promise = edge_nodes.then do |synced_nodes|
            start_cursor_promise = cursor_or_nil_from_node(synced_nodes.first)
            end_cursor_promise = cursor_or_nil_from_node(synced_nodes.last)
            ::Promise.all([start_cursor_promise, end_cursor_promise]).then do |start_cursor, end_cursor|
              PageInfo.new(connection: self, start_cursor: start_cursor, end_cursor: end_cursor)
            end
          end

          page_info_promise.sync
        end
      end

      # Zero out the expected results. Used in situations where the API AuthZ
      # check failed, and the resolvers are still expecting data to come through.
      # They should receive nothing, though.
      def none
        @edge_nodes = ::Promise.all([])
        self
      end

      def has_next_page
        # ensure initial data was loaded:
        results
        if !defined?(@has_next_page)
          @has_next_page = before ? inverse_relation_exists? : false
        end
        @has_next_page
      end

      def has_previous_page
        # ensure initial data was loaded:
        results
        if !defined?(@has_previous_page)
          @has_previous_page = after ? inverse_relation_exists? : false
        end
        @has_previous_page
      end

      def total_count
        # When taking the total count, remove the `ORDER BY` clause
        # because it doesn't change the outcome but it _does_
        # make the query harder for MySQL to run.
        # (Rails ends up making a `SELECT COUNT(*) FROM (...) AS subquery_for_count`)
        @total_count ||= if @items.group_values.any?
          # If the relation contains a `GROUP BY` instruction, calling `#count` will
          # return a `Hash` that has the aggregation column values as the keys, and the per-group count
          # as the respective values.
          #
          # As we're only interested in the overall count of result rows, we wrap the query
          # with an outer query that performs a plain count instead.
          #
          # The eventually executed query will look something like:
          #
          # ```
          # SELECT COUNT(*) FROM (SELECT 1 FROM ... WHERE ... GROUP BY ...) AS _subquery_for_count
          # ```
          @items.klass.from(@items.unscope(:order).unscope(:select).select("1"), :_subquery_for_count).count
        else
          @items.unscope(:order).unscope(:select).count
        end
      end

      private

      def cursor_or_nil_from_node(synced_node)
        if synced_node
          cursor_for(synced_node)
        else
          ::Promise.resolve(nil)
        end
      end

      # Returns the `after` cursor argument or nil.
      #
      # If a `numericPage` is present, compute the equivalent `after` cursor
      # from the relation.
      def after
        return @after if defined?(@after)

        if @arguments.present? && page = @arguments[:numeric_page]
          return if page == 1

          per_page = first
          last_page = (total_count / per_page.to_f).ceil

          page_containing_after_cursor  = page - 1
          offset_of_after_cursor        = (page_containing_after_cursor * per_page) - 1
          last_record_on_previous_page  = record_at_offset(page, last_page, offset_of_after_cursor)

          if last_record_on_previous_page.present?
            return @after = cursor_for(last_record_on_previous_page).sync
          end
        end

        super
      end

      # Returns an array of IDs
      def results
        @results ||= begin
          sliced_relation = apply_cursors(
            @items,
            after: after,
            before: before,
            inverse: false,
          )

          apply_limits(
            sliced_relation,
            first: first,
            last: last,
          )
        end
      end

      # Apply `.where` conditions to `relation` so that it is constrained
      # within `after` and `before` cursors.
      #
      # If `inverse` is true, build a relation on the "other side" of the cursor,
      # including the cursor itself, with a reverse ordering.
      def apply_cursors(relation, after:, before:, inverse:)
        if after
          values = decode_cursor(after)
          cursor_direction = inverse ? :before : :after
          conditions = Condition.build(@orderings, values, cursor_direction, equal_to: inverse)
          relation = relation.where(conditions)
        end

        if before
          values = decode_cursor(before)
          cursor_direction = inverse ? :after : :before
          conditions = Condition.build(@orderings, values, cursor_direction, equal_to: inverse)
          relation = relation.where(conditions)
        end

        if inverse
          relation = relation.reverse_order
        end

        relation
      end

      # Look for items on the _other side_ of the cursor.
      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def inverse_relation_exists?
        @inverse_relation_exists ||= apply_cursors(@items, after: after, before: before, inverse: true).exists?
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      def apply_limits(relation, first:, last:)
        if first
          ids = relation.limit(first + 1)
        elsif last
          ids = begin
            relation.reverse_order.limit(last + 1)
          rescue ActiveRecord::IrreversibleOrderError
            raise Errors::Execution, "Cannot paginate backwards on this connection using 'last', please use " \
              "'first' instead."
          end
        else
          raise Errors::Internal, "must limit connection with either first or last"
        end

        if sharded_table?(relation)
          # Vitess needs to select columns it is sorting by.
          order_by_columns = @orderings.
            select { |order| order.table != relation.klass.table_name || order.column != "id" }.
            map { |order| "#{order.table}.#{order.column}" }
          ids = ids.pluck(:id, *order_by_columns).map { |id, *_order_by_columns| id }
        else
          ids = ids.pluck(:id)
        end

        if last
          ids = ids.reverse
        end

        if first
          @has_next_page = ids.count > first
          ids = ids.first(first)
        end

        if last
          @has_previous_page = ids.count > last
          ids = ids.last(last)
        end

        ids
      end

      def encode_cursor(cursor_values)
        CursorGenerator.generate_cursor(cursor_values, version: :v2)
      end

      def decode_cursor(opaque)
        decoded_cursor = CursorGenerator.resolve_cursor(opaque)

        # Recent cursors have more than one value
        if decoded_cursor.is_a?(Array)
          decoded_cursor
        else
          # Old cursors don't have a primary key
          [decoded_cursor, nil]
        end
      end

      # Private: Get values for the cursor based on orderings and the result record
      #
      # result - An ActiveRecord::Base instance the cursor will be based on
      #
      # Returns a Promise that resolves to an array of ordering values,
      # including a primary key tiebreaker
      def fetch_ordering(result)
        ::Promise.all(
          @orderings.map { |o| o.apply_to(result) },
        )
      end

      def record_at_offset(page, last_page, offset)
        if page <= last_page
          @items.offset(offset).first
        else
          # FIXME: can we make this return a `NullRelation`?
          @items.last
        end
      end

      def sharded_table?(relation)
        relation.klass.superclass.name.include? "IssuesPullRequests"
      end

      def validate_security_violation_behavior!(behavior)
        return if behavior.nil?
        return if [:allow, :raise, :nil].include?(behavior)
        raise Platform::Errors::Internal, "Unknown security_violation_behaviour: #{behavior.inspect}"
      end

      def shard_key(relation_class)
        if relation_class.name == "Push" && @items.where_values_hash["repository_id"]
          { repository_id: @items.where_values_hash["repository_id"] }
        end
      end
    end
  end
end
