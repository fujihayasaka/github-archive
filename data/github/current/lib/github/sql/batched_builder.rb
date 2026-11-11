# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    class BatchedBuilder
      def initialize(start: 0, limit: 1000, connection:)
        @start = start
        @connection = connection
        @query_snippets = []
        @bindings = { start: start, limit: Arel.sql(limit.to_s) }
      end

      def add(*args)
        return if args.empty?

        @query_snippets << args.first
        @bindings.merge!(args.second) if args.second
      end

      def bind(*args)
        @bindings.merge! args.first
      end

      def batches
        validate_query!
        Enumerator.new do |batches|
          last = @start
          loop do
            query = build_query(last: last)
            batch = @connection.select_rows(query)
            break if batch.empty?

            batches << batch
            last = batch.last.first
          end
        end
      end

      def each
        rows.each do |row|
          yield row
        end
      end

      def rows
        Enumerator.new do |rows|
          batches.each do |batch|
            batch.each do |row|
              rows << row
            end
          end
        end
      end

      private

      def build_query(last:)
        bindings = @bindings.merge(last: last)
        query = Arel.sql("")
        @query_snippets.each do |sql|
          query += Arel.sql(sql, **bindings)
        end
        query
      end

      # Validate the query's binds and conditions, as best as possible.
      #
      # Requires a `LIMIT :limit` and `some_column > :last` clause.
      # Raises ArgumentError if not present.
      def validate_query!
        query_text = @query_snippets.join("\n")

        normalized = query_text.split(/\s+/).join(" ").downcase

        unless normalized =~ %r(\blimit :limit\b)
          raise ArgumentError, "Query missing `LIMIT :limit` clause: #{query_text}"
        end

        unless normalized =~ %r(>\s*:last)
          raise ArgumentError, "Query missing `column > :last` clause: #{query_text}"
        end

        unless normalized =~ %r(\border by\b)
          raise ArgumentError, "Query missing `ORDER BY` clause: #{query_text}"
        end

        column_name_match = %r{([\w.\`:]+)}
        select_match = normalized.match(%r{select\s(?:distinct\s)?(?<selected_column>#{column_name_match})})
        iterator_match = normalized.match(%r{(?<iterator_column>#{column_name_match})(?<last>\s>\s*:last)})

        unless select_match[:selected_column] == iterator_match[:iterator_column]
          raise ArgumentError, "First selected column must match column fed into :last binding: #{query_text}"
        end
      end
    end
  end
end
