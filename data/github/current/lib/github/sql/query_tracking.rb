# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    module QueryTracking
      extend self

      # Redact sql to remove sensitive and/or information not relevant to query tracking analysis
      # Returns a string.
      def redact_sql(sql)
        redacted = sql.gsub(";", "").gsub(/\/\*.*?\*\//, "").strip
        if redacted.start_with?("SELECT")
          redacted = redacted.gsub(/\ASELECT.+FROM/m, "SELECT ... FROM")
        elsif redacted.start_with?("INSERT INTO")
          redacted = redacted_sql_for_insert(redacted.gsub("`", ""))
        end
        redacted
      end

      # returns a string
      def redacted_sql_for_insert(query)
        table_name, columns, rows = parse_insert_query(query)

        if table_name.nil?
          ""
        else
          redacted_value_string = rows.map do |values|
            values.map.with_index do |value, index|
              columns[index].ends_with?("_id") ? value : "?"
            end.join(", ")
          end.join("), (")

          "INSERT INTO `#{table_name}` (#{columns.join(', ')}) VALUES (#{redacted_value_string})"
        end
      end

      # Returns a positional array
      def parse_insert_query(query)
        # Match INSERT INTO table_name (columns) VALUES (one or more values)
        match = query.match(/INSERT INTO\s+`?(?<table_name>\w+)`?\s*\((?<columns>[^)]+)\)\s+VALUES\s+(?<rows>.+?)(?:\s+ON DUPLICATE KEY UPDATE.*)?\z/m)

        unless match.nil?
          column_names = match[:columns].split(",").map { |name| name.gsub("`", "").strip }
          rows = match[:rows].split("), (").map do |values|
            values.split(",").map { |value| value.gsub("(", "").gsub(")", "").strip }
          end

          [match[:table_name], column_names, rows]
        end
      end

      # Returns queries that are unique by sql string, connection, and if it's part of a transaction
      # then scrubs sensitive/unnecessary information from sql string
      def unique_redacted_queries(queries)
        queries.uniq do |q|
          [q.sql, q.transaction_uuid, q.connection_class.try(:current_role), q.on_primary]
        end.map do |q|
          {
            redacted_sql: redact_sql(q.sql),
            digested_sql: q.digested_sql,
            transaction_uuid: q.transaction_uuid,
            connection_class_name: q.connection_class.try(:name),
            connection_class_role: q.connection_class.try(:current_role),
            on_primary: q.on_primary,
          }
        end
      end
    end
  end
end
