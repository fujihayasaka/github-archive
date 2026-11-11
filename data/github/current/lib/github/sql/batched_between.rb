# typed: true
# frozen_string_literal: true

module GitHub
  class SQL
    # Public: Build and iterate over a SQL query in batches,
    # using BETWEEN id AND (id + batch size) to retrieve and yield each batch.
    #
    # This can be helpful when the batching selects on where slow queries are a
    # concern as BETWEEN is more performant than WHERE id > :last (as seen in GitHub::SQL::Batched)
    #
    # Requirements:
    #
    # * The query has a condition with `:start` to constrain the start of the next iteration
    #   rows, e.g. `WHERE id BETWEEN :start AND :last`
    # * The query has a condition with `:last` to constrain the last seen id
    #   rows, e.g. `WHERE id BETWEEN :start AND :last`
    # * The query must return a value as the first item in each row which can be
    #   fed into the :last binding on each subsquent iteration. This value must be
    #   in ascending order.
    #
    # To build queries for a BatchedBetween instance, use the `add` and `bind` methods
    # just like you would with GitHub::SQL.
    #
    # Example: iterating over every repository, 20 at a time:
    #
    #   iterator = GitHub::SQL::BatchedBetween.new start: 0, batch_size: 20
    #   iterator.add <<-SQL
    #     -- id must go first for batched between to work properly
    #      SELECT id, other_fields
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
    #
    class BatchedBetween

      # Public: initialize a new BatchedBetween instance
      #
      # start - What id to start at when iterating. Used as the initial value of
      #         `:last` in the batch queries
      # finish - At what ID does iteration of batches terminate.
      #          MAX(id) is a common choice when iterating over an entire table.
      #          Finish is the final maximum value of :last
      # batch_size - Increments the BETWEEN range by this much on each iteration.
      # query_builder - an instance of ApplicationRecord::Base::GitHubSQLBuilder
      def initialize(start:, finish:, batch_size: 1000, query_builder:)
        @start = start
        @finish = finish
        @batch_size = batch_size
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
            break if next_id > @finish
            query = build_query start: next_id, last: (next_id + @batch_size)
            batch = query.results

            batches << batch if !batch.empty?
            next_id = get_next_id(batch, next_id)
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
        query = @query_builder.new(last: [last, @finish].min, start: start)
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
      # Raises ArgumentError if not present.
      def validate_query!
        query_text = @query.select { |q| q.first == :add }.map { |(_add, args)| args.first }.join("\n")
        normalized = query_text.split(/\s+/).join(" ").downcase

        unless normalized =~ %r(between\s*:start and :last)
          raise ArgumentError, "Query missing `WHERE id BETWEEN :start AND :last` clause: #{query_text}"
        end

        column_name_match = %r{([\w.\`:]+)}
        select_match = normalized.match(%r{select\s(?:distinct\s)?(?<selected_column>#{column_name_match})})
        iterator_match = normalized.match(%r{(?<iterator_column>#{column_name_match})\s(?<between>between\s*:start and :last)})

        unless select_match[:selected_column] == iterator_match[:iterator_column]
          raise ArgumentError, "First selected column must match column fed into :between binding: #{query_text}"
        end
      end

      # Internal: calculate the next_id to start from.
      #
      # If the batch is empty then move to the next batch, otherwise
      # take the last id from the current batch
      def get_next_id(batch, next_id)
        if batch.empty? && next_id <= @finish
          # the last batch was empty and we have not reached max_id yet
          next_id = next_id + @batch_size + 1
        else
          # The next iterations start id should be the last id seen in this set
          # incremented by one to avoid duplicate selection.
          next_id = batch.last.first + 1
        end
      end
    end
  end
end
