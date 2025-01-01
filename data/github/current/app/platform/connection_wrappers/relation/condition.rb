# typed: false
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Relation
      module Condition
        include Kernel
        extend T::Sig

        module_function

        COMPARATORS = {
          before: {
            "ASC" => "<",
            "asc" => "<",
            "DESC" => ">",
            "desc" => ">",
          },
          after: {
            "ASC" => ">",
            "asc" => ">",
            "DESC" => "<",
            "desc" => "<",
          },
        }

        CURSOR_CONDITION = "%{table}.%{column} %{comparator} ?"

        CURSOR_CASE = "(%{case}) %{comparator} ?"

        CURSOR_FIELD = "FIELD(%{table}.%{column}, %{field_values_list}) %{comparator} ?"

        # Prepare a SQL condition for a relation to resume pagination from either `before` or `after`.
        #
        # orderings - an array of hashes identifing information about the various sort orderings. the keys are:
        #             table - The table being sorted
        #             column - The column being acted on
        #             direction - The direction of the sort
        #             type - The data type of the column / field
        # values   - an array of data values for the last cursor position
        # cursor_direction    - a symbol of either `:before` or `:after`
        # equal_to - if true, conditions will use "equal-to" variants (eg `>` becomes `>=`).
        #            This is useful for finding records which _match_ cursor values (implementing reverse pagination checks)
        #
        # Returns an Array suitable for `ActiveRecord::Relation#where`.
        def build(orderings, values, cursor_direction, equal_to:)
          # This is for backwards compatibility.
          # For a while, we ignored case statements when building cursors,
          # but now we use them. So some old cursors contain one-too-few values.
          # We can adjust for that and serve a response, although the response might be buggy.
          # (The new response will have full-length cursors.)
          applicable_orderings = if (orderings.size - values.size) == 1
            orderings.reject(&:case_clause)
          else
            orderings
          end

          orders = { statement: [], values: [] }
          conditions = construct_ordering(orders, applicable_orderings, values, cursor_direction, equal_to: equal_to)
          statement = conditions[:statement].map { |statement| "(#{statement})" }.join(" OR ")
          [statement].concat(conditions[:values])
        end

        # Don't be scared by the recursion here! It's actually quite simple: given
        # an arbitrary listing of ordering rules, this assembles an array that combines
        # those queries into progressively permissive patterns. For example,
        # given:
        #
        # orderings = [
        #     { table: repositories, column: name, direction: ASC },
        #     { table: repositories, column: created_at, direction: ASC },
        #     { table: repositories, column: id, direction: ASC }
        # ]
        #
        # and:
        #
        # values = [ "ABC", 2017-01-01, 6]
        #
        # This loop would construct a statement that looks like this:
        #
        # (name > "ABC") OR (name = "ABC" AND created_at > 2017-01-01) OR (name = "ABC" AND created_at = 2017-01-01 AND id > 6)
        #
        # This would allow a cursor to retain its sorting knowledge, given an arbitrary sequence of sorts
        def construct_ordering(orders, orderings, values, cursor_direction, equal_to:)
          current_size = orders[:statement].size
          if current_size == orderings.size
            # We visited each ordering, we can stop now
            orders
          else
            combinator = []
            (0..current_size).each do |idx|
              ordering = orderings[idx]

              value = begin
                ordering.coerce_value(values[idx])
              rescue Ordering::CoercionError
                raise Errors::Cursor.new
              end

              last_condition = idx == current_size
              if last_condition
                comparator = COMPARATORS
                  .fetch(cursor_direction)
                  .fetch(ordering.direction)

                if equal_to
                  comparator += "="
                end
              else
                comparator = "="
              end

              if ordering.case_clause
                template_values = {
                  case: ordering.case_clause,
                  comparator: comparator,
                }
                combinator << CURSOR_CASE % template_values
                orders[:values] << value
              elsif ordering.field_values
                combinator << CURSOR_FIELD % {
                  table: ordering.table,
                  column: ordering.column,
                  field_values_list: ordering.field_values.join(","),
                  comparator: comparator,
                }
                orders[:values] << value
              else
                template_values = {
                  table: ordering.table,
                  column: ordering.column,
                  comparator: comparator,
                }

                combinator << CURSOR_CONDITION % template_values
                orders[:values] << value
              end
            end

            orders[:statement] << combinator.join(" AND ")
            construct_ordering(orders, orderings, values, cursor_direction, equal_to: equal_to)
          end
        end
      end
    end
  end
end
