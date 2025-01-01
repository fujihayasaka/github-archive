# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    # The base class for the components of an AST. Each component represents part of the query that will be sent
    # to Elasticsearch in MemexProjectItemQuery.
    class Node
      extend T::Helpers
      abstract!

      sig { returns(T::Array[Node]) }
      attr_accessor :children

      sig { params(children: T::Array[Node]).void }
      def initialize(children = [])
        @children = children
      end

      sig { abstract.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
      def compile(context); end

      sig(:final) { params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
      def compile_as_must_query(context)
        result = compile(context)
        if result.dig(:bool, :should)
          # Wrap with 'bool' 'must' to ensure that it properly ANDs all field query fragments
          # when merging them together
          { bool: { must: [result] } }
        else
          result
        end
      end
    end
  end
end
