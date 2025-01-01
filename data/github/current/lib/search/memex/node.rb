# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    # The base class for the components of an AST. Each component represents part of the query that will be sent
    # to Elasticsearch in MemexProjectItemQuery.
    class Node
      extend T::Sig
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
    end
  end
end
