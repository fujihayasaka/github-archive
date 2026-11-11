# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Represents an OR expression between two or more query segments.
      # Each segment is an array of Nodes that are AND-combined within the segment.
      # The segments themselves are OR-combined using Elasticsearch's `bool.should`.
      #
      # Example query: "is:open OR labels:bug"
      # Produces ES:
      #   { bool: { should: [<compiled is:open>, <compiled labels:bug>], minimum_should_match: 1 } }
      class OrGroup < Node
        include DeepMergeHelpers

        sig { returns(T::Array[T::Array[Node]]) }
        attr_reader :or_segments

        sig { params(or_segments: T::Array[T::Array[Node]]).void }
        def initialize(or_segments:)
          super()
          @or_segments = or_segments
        end

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          should_clauses = @or_segments.filter_map do |segment_nodes|
            combined = segment_nodes
              .map { |node| node.compile_as_must_query(context) }
              .inject({}) { |acc, result| deep_merge_query(acc, result) }
            combined.empty? ? nil : combined
          end

          return {} if should_clauses.empty?
          return should_clauses.first if should_clauses.length == 1

          { bool: { should: should_clauses, minimum_should_match: 1 } }
        end

        sig { override.returns(String) }
        def query_string
          @or_segments.map { |segment| segment.map(&:query_string).join(" ") }.join(" OR ")
        end

        # Returns true if any node in any segment is a sub-issue filter.
        sig { override.returns(T::Boolean) }
        def sub_issue_filter?
          @or_segments.any? { |segment| segment.any?(&:sub_issue_filter?) }
        end
      end
    end
  end
end
