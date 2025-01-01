# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Relation
      class Ordering
        class CoercionError < ArgumentError; end

        # The name of the table being ordered
        attr_reader :table

        # The name of the coumn being ordered
        attr_reader :column

        # The sort order (ASC or DESC)
        attr_reader :direction

        # The data type for this column
        attr_reader :type

        # If this ordering was CASE ..., the clause parsed as a hash.
        # i.e.
        #     CASE foo WHEN bar THEN 1 WHEN baz THEN 2 ELSE 3
        # parses as
        #   {"bar" => 1, "baz" => 2}
        # with the ELSE stored in `miss`.
        attr_reader :parsed_case_clause
        attr_reader :case_clause

        # If this ordering was FIELD(id,...)
        attr_reader :field_values

        def initialize(table:, column:, direction:, type:, parsed_case_clause: nil, case_clause: nil, miss: nil, field_values: nil)
          @table = table
          @column = column
          @direction = direction
          @type = type
          # This is used for replaying case statements on individual records, for building cursors
          @parsed_case_clause = parsed_case_clause
          @case_clause = case_clause
          @miss = miss
          # This is used for replaying field statements
          @field_values = field_values
        end

        # Apply this ordering to `record`, returning a Promise that resolves to the value it was
        # ordered by. This is usually a column value, but:
        #   * if the order-by was a CASE statement, then we replay that case statement in Ruby. :scream:.
        #   * if the order-by was a FIELD statement, we unwrap the list to find the proper index. :scream:
        #   * if the order-by was on a different table, we (try to) reflect on the associated record to get the value :scream:
        def apply_to(record)
          value = if record.class.table_name == @table
            record[@column]
          end

          # Apply the case logic
          if @parsed_case_clause
            value = @parsed_case_clause[value] || @miss
          end

          # Find the entry if present, and then convert to 1-indexed,
          # if not present use 0
          if @field_values
            value = (@field_values.index(value) || -1) + 1
          end

          value ||= try_to_get_value_from_association(record)

          ::Promise.resolve(value).then do |val|
            if val && time_type?
              val.iso8601(@type.precision)
            else
              val
            end
          end
        end

        def time_type?
          [:datetime, :timestamp, :time].include?(@type.type)
        end

        # Coerce a value from a cursor to a valid database value
        # raises CoercionError if the value could not be coerced to the right type.
        def coerce_value(value)
          return if value.nil?

          coerced = @type.cast(value)

          if coerced.nil? || !valid_type_value?(coerced)
            raise CoercionError # rubocop:disable GitHub/UsePlatformErrors
          end

          coerced
        end

        private

        def valid_type_value?(value)
          case @type.type
          when :datetime, :time
            value.is_a?(Time)
          when :integer, :float, :decimal
            value.is_a?(Numeric)
          when :string
            value.is_a?(String)
          else
            true
          end
        end

        def try_to_get_value_from_association(record)
          if (
            record.is_a?(Repository) &&
            @table == "repository_topics" &&
            @column == "repository_id"
          )

            return record[:id]
          end
          if record.is_a?(Star) && @table == "repositories"
            value = Loaders::ActiveRecordAssociation.load(record, "starrable").then do |starrable|
              if starrable.is_a?(Repository)
                starrable[@column]
              end
            end
          end
        end

        class << self # rubocop:disable Style/ClassMethodsDefinitions
          # Returns two things:
          #  - A new relation (may get a new order by ID to ensure stability)
          #  - An array of Orderings which reflects that relation
          def from_relation(relation)
            orderings = extract_relation_order(relation)

            # If this relation isn't _already_ sorted by primary key,
            # add a bonus ordering by primary_key to make sure that the cursor is stable
            if orderings.none? { |o| o.table == relation.table_name && o.column == relation.primary_key }
              primary_cursor_direction = orderings.empty? ? "ASC" : orderings.first.direction
              relation = relation.order("#{relation.table_name}.#{relation.primary_key} #{primary_cursor_direction}")
              type = cursor_column_type(relation: relation, table_name: relation.table_name,
                                        cursor_column: relation.primary_key)
              orderings << self.new(
                table: relation.table_name,
                column: relation.primary_key,
                direction: primary_cursor_direction,
                type: type,
              )
            end

            [relation, orderings]
          end

          def cursor_column_type(relation:, table_name:, cursor_column:)
            type = if relation.klass.table_name == table_name
              # e.g. if we have a Repository relation and ordering by `repositories.name`,
              # get the column object corresponding to Repository#name
              relation.klass.type_for_attribute(cursor_column.to_s)
            elsif (klass = table_name.classify.safe_constantize) && klass.respond_to?(:columns_hash)
              # e.g. if we have a Star relation and ordering by `repositories.pushed_at`,
              # get the column object corresponding to Repository#pushed_at
              klass.type_for_attribute(cursor_column.to_s)
            end

            if type.nil?
              raise Platform::Errors::Internal, <<~ERR
                Cannot derive SQL type for ordering column: `#{table_name}`.`#{cursor_column}`"

                Contact #graphql for help refactoring this connection
                or modifying the logic to support this SQL ordering.
              ERR
            end

            type
          end

          # Match SQL `ORDER` clauses, `table.column DIRECTION`
          ORDER_CLAUSE_REGEXP = /\A`?(?:(?<table>[a-z_0-9]+)`?\.)?`?(?<column>[a-z_0-9]+)`?\s?(?<direction>ASC|DESC)?\z/i

          # Match SQL orders like `FIELD(id, ...)`
          # When objects are ordered in some arbitrary, explicit way.
          EXPLICIT_ID_ORDER_CLAUSE_REGEXP = /\AFIELD\((?<table>[a-z_0-9]+\.)?(?<column>[a-z_0-9]+),(?<field_values>[\d\s,']*)\)\s?(?<direction>ASC|DESC)?\z/i

          # Match SQL orders like `CASE WHEN column = 'Some value' THEN... ELSE ... END`
          # This is tailored to our use cases, feel free to improve this pattern if more uses arise.
          COLUMN_CASE_ORDER_CLAUSE_REGEXP = /\ACASE\s+(?<body>.*)\s+ELSE\s+(?<miss>\d+)\s+END/i
          # A regex suitable for use with String.scan that can extract all case expressions.
          CASE_PARSER = /\s*WHEN\s+((?<table>[a-z_0-9]+)\.)?(?<column>[a-z_0-9]+)`?\s*=\s*'(?<value>[\w\s]*)'\s+THEN\s+(?<hit>\d+)\s*/i

          # Obtains the order from the given relation
          #
          # Returns an array containing the table name, column, and order direction.
          def extract_relation_order(relation)
            order_values = relation.order_values.uniq

            orderings = order_values.each_with_object([]) do |order_value, arr|
              match_data = order_info(order_value, relation)
              case match_data
              when nil
                raise Platform::Errors::Internal, <<~ERR
                  Failed to understand SQL ordering: #{order_value.inspect}.
                  Can't create a stable cursor for this ordering.

                  If your order clause contains several comma-separated orders,
                  try splitting them up into separate clauses, for example:

                    # before
                    .order("id, created_at")
                    # after
                    .order("id").order("created_at")

                  That way, we can build the cursor using one order clause at a time.

                  Contact #graphql for help refactoring this connection
                  or modifying the logic to support this SQL ordering.
                ERR
              else
                table = match_data["table"] || relation.table_name
                column = match_data["column"]
                direction = match_data["direction"] || "ASC"

                type = cursor_column_type(relation: relation, table_name: table,
                                          cursor_column: column)

                ordering_attrs = {
                  table: table,
                  column: column,
                  direction: direction,
                  type: type,
                }

                if match_data.key?("case")
                  # It's a COLUMN_CASE_ORDER_CLAUSE_REGEXP match
                  ordering_attrs.merge!({
                    case_clause: match_data["case"],
                    parsed_case_clause: match_data["parsed_case_clause"],
                    miss: match_data["miss"].to_i,
                  })
                end

                if match_data.key?("field_values")
                  # It's an EXPLICIT_ID_ORDER_CLAUSE_REGEXP match
                  ordering_attrs[:field_values] = match_data["field_values"].strip.split(/[,\s]+/)
                    .map { |str| str.sub(/\A'/, "").sub(/'\z/, "").to_i }
                end

                arr << self.new(**ordering_attrs)
              end
            end

            raise_if_field_with_no_column_order(orderings) if Rails.env.test? || Rails.env.development?

            orderings
          end

          def raise_if_field_with_no_column_order(orderings)
            orderings.select(&:field_values).each do |ordering|
              next if orderings.any? { |o| o.field_values.nil? }

              raise Platform::Errors::Internal, <<~ERR
                It looks like you're using FIELD(#{ordering.column}, ...) to
                order a collection of records.  Due to how we define cursors
                for these types of queries, you'll also need to explicitly add
                a secondary ordering that will be used for sorting records that
                do not appear in your FIELD list.

                In most cases, you'll want to add something like this to your
                query builder:

                  .order("#{ordering.column}")

                Contact #graphql for more help as necessary.
              ERR
            end
          end

          # Private: Turn an ordering from ActiveRecord into a data structure
          # which we can use to rebuild a cursor.
          #
          # Returns either:
          #  - A string-keyed hash of parsed order data
          #  - `:require_next_id_order`, a flag that this ordering may be ignored for cursor generation
          #  - nil
          def order_info(order, relation)
            case order
            when Arel::Nodes::Descending, Arel::Nodes::Ascending
              case order.expr
              when Arel::Nodes::SqlLiteral
                order_info_from_string("#{order.expr} #{order.direction}")
              when Arel::Attributes::Attribute
                order_info_from_arel_attribute(order.expr).merge("direction" => order.direction.to_s)
              end
            when String, Symbol
              order_info_from_string(order.to_s)
            else
              order_info_from_arel_attribute(order.expr).merge("direction" => order.direction.to_s)
            end
          end

          # Private: Get information about how a SQL query is ordered.
          #
          # arel_attribute - an Arel::Attributes::Attribute, see
          #                  https://www.rubydoc.info/gems/arel/Arel/Attributes/Attribute
          #
          # Returns a Hash with String keys.
          def order_info_from_arel_attribute(arel_attribute)
            { "table" => arel_attribute.relation.name, "column" => arel_attribute.name.to_s }
          end

          # Private: Get information about how a SQL query is ordered.
          #
          # order_str - a String of text following an `ORDER BY` clause from a SQL query, e.g., "name ASC" or
          #             "FIELD(users.id, 1,2,3), id"
          #
          # Returns a Hash with String keys, or nil.
          def order_info_from_string(order_str)
            if EXPLICIT_ID_ORDER_CLAUSE_REGEXP.match(order_str)
              captures = $~.named_captures
              if captures["table"]
                captures["table"] = captures["table"].sub(/\.\z/, "")
              end
              captures
            elsif ORDER_CLAUSE_REGEXP.match(order_str)
              $~.named_captures
            elsif COLUMN_CASE_ORDER_CLAUSE_REGEXP.match(order_str)
              result = $~.named_captures.merge("case" => order_str)
              result["table_column_pairs"] = []

              case_tuples = result["body"].scan(CASE_PARSER)
              parsed_case_clause = case_tuples.map do |table, column, condition, value|
                result["column"] = column
                result["table"] = table
                result["table_column_pairs"] << "#{table}#{column}"
                [condition, value.to_i]
              end.to_h

              if result["table_column_pairs"].uniq.size > 1
                raise Platform::Errors::Internal,
                  "all case conditions must use the same table and column: #{order_str.inspect}"
              end

              result.merge("parsed_case_clause" => parsed_case_clause)
            else
              nil
            end
          end
        end
      end
    end
  end
end
