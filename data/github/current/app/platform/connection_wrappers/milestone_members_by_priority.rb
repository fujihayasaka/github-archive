# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This is a special case for an ActiveRecord Relation which is sorted by a join table,
    # and the joined value is required later.
    #
    # Our usual ConnectionWrappers::Relation discards any joined records because it
    # refetches by ID. But this one keeps those joined records attached.
    #
    # The other trick here is that some milestones have `.issues`, but not
    # `.issue_priorities`. (For example https://github.com/crystal-lang/crystal/milestone/26)
    # In this case, they're sorted by ID
    class MilestoneMembersByPriority < ConnectionWrappers::Base
      def initialize(items, **kwargs)
        @loaded = false
        super(items, **kwargs)
      end

      def nodes
        load_data
        @nodes
      end

      def has_next_page
        load_data
        @has_next_page
      end

      def has_previous_page
        load_data
        @has_previous_page
      end

      def cursor_for(item)
        CursorGenerator.generate_cursor([item.priority, item.id], version: :v2)
      end

      def total_count
        items.length
      end

      private

      def id_and_priority_from_cursor(cursor)
        CursorGenerator.resolve_cursor(cursor)
      end

      def load_data
        # Don't re-run this method
        if @loaded
          return
        end
        @loaded = true

        nodes_within_cursors = items
        table_name = items.klass.table_name
        if after
          priority, id = id_and_priority_from_cursor(after)
          # If the priority is nil, then we're filtering by ID
          nodes_within_cursors = nodes_within_cursors.where("(issue_priorities.priority IS NULL AND #{table_name}.id > ?) OR issue_priorities.priority < ?", id, priority)
        end

        if before
          priority, id = id_and_priority_from_cursor(before)
          # If the priority is nil, then we're filtering by ID
          nodes_within_cursors = nodes_within_cursors.where("(issue_priorities.priority IS NULL AND #{table_name}.id < ?) OR issue_priorities.priority > ?", id, priority)
        end

        if first
          nodes_within_cursors = nodes_within_cursors.limit(first + 1)
        elsif last
          nodes_within_cursors = nodes_within_cursors.reverse_order.limit(last + 1)
        end

        # Run the database query
        all_nodes = nodes_within_cursors.to_a

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

        @nodes = all_nodes
      end
    end
  end
end
