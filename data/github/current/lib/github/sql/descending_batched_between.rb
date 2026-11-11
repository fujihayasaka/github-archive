# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    # Public: Build and iterate over a SQL query in batches,
    # using BETWEEN (id - batch size) AND id to retrieve and yield each batch.
    #
    # Requirements:
    #
    # * The query has a condition with `:start` to constrain the start of the next iteration
    #   rows, e.g. `WHERE id BETWEEN :start AND :last`
    # * The query has a condition with `:last` to constrain the last seen id
    #   rows, e.g. `WHERE id BETWEEN :start AND :last`
    # * The query has an ORDER BY attr DESC clause
    # * The query must return a value as the first item in each row which can be
    #   fed into the :last binding on each subsquent iteration. This value must be
    #   in descending order.
    #
    # To build queries for a DescendingBatchedBetween instance, use the `add` and `bind` methods
    # just like you would with GitHub::SQL.
    #
    # Example: iterating over every repository, 20 at a time:
    #
    #   iterator = GitHub::SQL::BatchedBetween.new start: 40, finish: 0, batch_size: 20
    #   iterator.add <<-SQL
    #      SELECT id
    #      FROM users
    #     WHERE id BETWEEN :start AND :last
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
    class DescendingBatchedBetween
      attr_reader :start, :finish

      # Public: initialize a new BatchedBetween instance
      #
      # start - What id to start at when iterating. Used as the initial value of
      #         `:last` in the batch queries
      # finish - At what ID does iteration of batches terminate.
      #          MIN(id) is a common choice when iterating over an entire table.
      #          Finish is the final minimum value of :start
      # batch_size - Decrements the BETWEEN range by this much on each iteration.
      # query_builder - an instance of ApplicationRecord::Base::GitHubSQLBuilder
      def initialize(start:, finish:, batch_size: 1000, query_builder:)
        @start = start
        @finish = finish

        if @start < @finish
          raise ArgumentError.new(":start must be greater than :finish.")
        end

        @batch_size = batch_size

        if @batch_size <= 1
          raise ArgumentError.new(":batch_size must be greater than 1")
        end

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
          next_id = @start
          loop do
            break if next_id < @finish

            # NOTE:
            # SQL BETWEEN expects BETWEEN <low value> AND <high value>, it does
            # not support BETWEEN <high value> and <low value>
            #
            # SQL BETWEEN is inclusive so we subtract one from batch size to avoid
            # selecting duplicates
            query = build_query start: (next_id - (@batch_size - 1)), last: next_id
            batch = query.results

            batches << batch if !batch.empty?
            next_id = next_id - @batch_size
          end
        end
      end

      # Public: add additional bind values to the iterator's queries.
      #
      # Delegates to GitHub::SQL#bind.
      def bind(*args)
        @query << [:bind, args]
      end

      # Internal: build a query for an iteration, using start and last values.
      def build_query(start:, last:)
        query = @query_builder.new(start: [start, @finish].max, last: last)
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
      # Requires a `WHERE id BETWEEN :start AND :last` clause.
      # Requires a `ORDER BY x DESC` clause.
      # Raises ArgumentError if not present.
      def validate_query!
        query_text = @query.select { |q| q.first == :add }.map { |(_add, args)| args.first }.join("\n")
        normalized = query_text.split(/\s+/).join(" ").downcase

        unless normalized =~ %r(between\s*:start and :last)
          raise ArgumentError, "Query missing `WHERE id BETWEEN :start AND :last` clause: #{query_text}"
        end

        unless normalized =~ %r(order\s*by\s*\w*\s*desc)
          raise ArgumentError, "Query missing `ORDER BY column DESC` clause: #{query_text}"
        end
      end
    end
  end
end
