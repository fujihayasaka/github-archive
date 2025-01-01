# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Queries
    module Trino
      class Base
        extend T::Helpers
        abstract!

        TRINO_QUERY_RESULTS_LIMIT = T.let(1_000_000, Integer)

        sig { params(query: T.nilable(String), query_name: T.nilable(String)).void }
        def initialize(query: nil, query_name: nil)
          @query = query
          @query_name = query_name
        end

        # Executes the Trino query and returns the results.
        # It also tracks the execution time and increments the query counts in DataDog.
        #
        # The results are returned as an array of rows with each element being a nested array of different column values.
        # For example: [["column1_value1", "column2_value1"],["column1_value2", "column2_value2"]]
        # The caller is responsible for flattening or mapping the results if needed.
        #
        # Additionally, GitHub.trino.run returns column metadata in the result set, but this method ignores it.
        sig { returns(T::Array[T.untyped]) }
        def run_query
          query_start_time = T.let(Time.now.utc, Time)
          _, results = T.unsafe(GitHub.trino).run(query)
          time_elapsed = GitHub::Dogstats.duration(query_start_time, Time.now.utc)
          GitHub.dogstats.increment("dependency_graph.trino.query_count", tags: ["query:#{query_name}"])
          GitHub.dogstats.distribution("dependency_graph.trino.query_duration", time_elapsed, tags: ["query:#{query_name}"])
          results
        end

        private

        # The name of the query. This should be defined in subclasses.
        sig { returns(String) }
        def query_name
          raise ArgumentError, "#{self.class} must define a non-empty query_name" if @query_name.to_s.strip.empty?
          T.must(@query_name)
        end

        # The SQL query string. This should be defined in subclasses.
        sig { returns(String) }
        def query
          @query || build_query
        end

        # Abstract method to build the SQL query string.
        sig { abstract.returns(String) }
        def build_query; end

        # Add a limit clause to the SQL query string, respecting the maximum limit set by TRINO_QUERY_RESULTS_LIMIT.
        sig { params(limit: T.nilable(Integer)).returns(String) }
        def limit_query_string(limit)
          raise ArgumentError, "limit must be a number > 0" if !limit.nil? && (limit < 1)
          limit = TRINO_QUERY_RESULTS_LIMIT if !limit || limit > TRINO_QUERY_RESULTS_LIMIT
          "LIMIT #{limit}"
        end
      end
    end
  end
end
