# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Milestone < ConnectionWrappers::Base
      ORDER_FIELD_SQL = {
        "due_date"     => "milestones.due_on",
        "created_at"   => "milestones.created_at",
        "updated_at"   => "milestones.updated_at",
        "number"       => "milestones.number",
        "completeness" => "(milestones.closed_issue_count / (milestones.open_issue_count + milestones.closed_issue_count))",
        "count"        => "(milestones.open_issue_count + milestones.closed_issue_count)",
        "title"        => "milestones.title"
      }.freeze


      def initialize(items, **kwargs)
        @loaded = false
        super(items, **kwargs)
      end

      def nodes
        load_data unless @loaded
        @nodes
      end

      def has_next_page
        load_data unless @loaded
        @has_next_page
      end

      def has_previous_page
        load_data unless @loaded
        @has_previous_page
      end

      def cursor_for(item)
        order_expression = if arguments[:order_by] && arguments[:order_by].field == "due_date"
          item.due_on ? item.due_on.iso8601(0) : nil
        elsif arguments[:order_by] && arguments[:order_by].field == "created_at"
          item.created_at.iso8601(0)
        elsif arguments[:order_by] && arguments[:order_by].field == "updated_at"
          item.updated_at.iso8601(0)
        elsif arguments[:order_by] && arguments[:order_by].field == "number"
          item.number
        elsif arguments[:order_by] && arguments[:order_by].field == "completeness"
          item.open_issue_count + item.closed_issue_count > 0 ? item.closed_issue_count.to_f / (item.open_issue_count + item.closed_issue_count).to_f : nil
        elsif arguments[:order_by] && arguments[:order_by].field == "count"
          item.open_issue_count + item.closed_issue_count
        elsif arguments[:order_by] && arguments[:order_by].field == "title"
          item.title
        else
          0
        end
        CursorGenerator.generate_cursor([order_expression, item.id], version: :v2)
      end

      def total_count
        items.unscope(:order).unscope(:select).count
      end

      private

      def id_and_expression_from_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor)
      end

      def build_nodes_within_cursors(nodes_within_cursors, compare_operator)
        expression, id = if before
          id_and_expression_from_cursor(before)
        else
          id_and_expression_from_cursor(after)
        end
        if arguments[:order_by]
          field = arguments[:order_by].field
          sql_field = ORDER_FIELD_SQL[field]

          if expression.nil?
            nodes_within_cursors.where(
              "(#{sql_field} is not NULL) OR (#{sql_field} is NULL AND milestones.id #{compare_operator} ?)", id)
          else
            # Cast expression if required
            if %w[due_date created_at updated_at].include?(field)
              expression = ActiveRecord::Type::DateTime.new(precision: 0).cast(expression)
            end
            nodes_within_cursors.where(
              "(#{sql_field} #{compare_operator} ?) OR (#{sql_field} = ? AND milestones.id #{compare_operator} ?)",
              expression, expression, id
            )
          end
        else
          nodes_within_cursors.where(
            "(milestones.id > ?)",
            id
          ).order("milestones.id ASC")
        end
      end

      def load_data
        nodes_within_cursors = items
        compare_operator = arguments[:order_by] && arguments[:order_by].direction == "ASC" ? ">" : "<"
        if first
          nodes_within_cursors = nodes_within_cursors.limit(first + 1)
        elsif last
          nodes_within_cursors = nodes_within_cursors.reverse_order.limit(last + 1)
          compare_operator = arguments[:order_by] && arguments[:order_by].direction == "ASC" ? "<" : ">"
        end

        if before || after
          nodes_within_cursors = build_nodes_within_cursors(nodes_within_cursors, compare_operator)
        else
          nodes_within_cursors = nodes_within_cursors.order("milestones.id ASC")
        end

        # Run the database query
        timer = Timer.start
        all_nodes = nodes_within_cursors.to_a
        timer.stop
        GitHub.dogstats.distribution("graphql.connection.milestone.time", timer.elapsed_ms, tags: ["order_by:#{arguments[:order_by]&.field || "id"}", "operation_name:#{context[:query_name]}"])

        # We'll check some conditions and
        # set these to true below if they apply
        @has_next_page = false
        @has_previous_page = false
        if first
          if all_nodes.size == first + 1
            @has_next_page = true
            all_nodes = all_nodes.first(first)
          end
        elsif last
          if all_nodes.size == last + 1
            @has_previous_page = true
            all_nodes = all_nodes.first(last)
          end
          all_nodes = all_nodes.reverse
        end
        @loaded = true
        @nodes = all_nodes
      end
    end
  end
end
