# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    # Public: Build and iterate over a SQL query in batches, using a minimum ID
    # and maximum LIMIT to retrieve and yield each batch.
    #
    # Requirements:
    #
    # * The query has a condition with `:last` to skip examining already-seen
    #   rows, e.g. `WHERE id > :last`
    # * The query must return a value as the first item in each row which can be
    #   fed into the :last binding on each subsquent iteration. This value must be
    #   in ascending order.
    # * The query must include a `LIMIT :limit` clause to limit results.
    #   (Otherwise, just use GitHub::SQL directly!)
    #
    # To build queries for a Batched instance, use the `add` and `bind` methods
    # just like you would with GitHub::SQL.
    #
    # Example: iterating over every repository, 20 at a time:
    #
    #   iterator = GitHub::SQL::Batched.new start: 0, limit: 20
    #   iterator.add <<-SQL
    #     SELECT r.id, CONCAT_WS('/', name, login) nwo
    #     FROM repositories r
    #     JOIN users u ON r.owner_id = u.id
    #     WHERE r.id > :last
    #     ORDER BY r.id
    #     LIMIT :limit
    #   SQL
    #   iterator.each { |id, nwo| puts "repo #{id} is #{nwo}" }
    #
    # To access each row as an Enumerator:
    #
    #   iterator.rows.each { |row| ... }
    #
    # Or each batch, again as an Enumerator:
    #
    #   iterator.batches.each { |rows| ... }
    #
    # Or, to just process each row directly:
    #
    #   iterator.each do |row|
    #     # row is [id, created_at]
    #   end
    #
    # Iteration continues until the result set is empty.
    #
    class Batched
      # Public: initialize a new Batched instance
      #
      # start - What id to start at when iterating. Used as the initial value of
      #         `:last` in the batch queries. Defaults to 0.
      # limit - How many rows to retrieve at a time. Inserted into the batch
      #         queries as `:limit`. Defaults to 1000.
      # query_builder - an instance of ApplicationRecord::Base::GitHubSQLBuilder
      def initialize(start: 0, limit: 1000, query_builder:)
        @start = start
        @limit = limit
        @query = []
        @query_builder = query_builder
      end

      # Public: add a chunk of SQL to the iterator's queries.
      #
      # Delegates to GitHub::SQL#add.
      def add(*args)
        @query << [:add, args]
      end

      # Public: Retrieve and yield results in batches.
      #
      # Returns an Enumerator.
      def batches
        validate_query!

        Enumerator.new do |batches|
          last = @start
          loop do
            query = build_query last: last
            batch = query.results

            break if batch.empty?
            batches << batch
            last = batch.last.first
          end
        end
      end

      # Public: add additional bind values to the iterator's queries.
      #
      # Delegates to GitHub::SQL#bind.
      def bind(*args)
        @query << [:bind, args]
      end

      # Internal: build a query for an iteration, using last and limit values.
      def build_query(last:)
        query = @query_builder.new(last: last, limit: @limit)
        @query.each do |method, args|
          query.public_send method, *args
        end
        query
      end

      # Public: Retrieve results in batches, yielding each row in turn.
      def each
        rows.each do |row|
          yield row
        end
      end

      # Public: Retrieve results in batches, yielding each row.
      #
      # Returns an Enumerator.
      def rows
        Enumerator.new do |rows|
          batches.each do |batch|
            batch.each do |row|
              rows << row
            end
          end
        end
      end

      # Internal: validate the query's binds and conditions, as best as possible.
      #
      # Requires a `LIMIT :limit` and `some_column > :last` clause.
      # Raises ArgumentError if not present.
      def validate_query!
        query_text = @query.select { |q| q.first == :add }.map { |(_add, args)| args.first }.join("\n")

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
