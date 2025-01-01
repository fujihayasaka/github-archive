# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    # Abstract Syntax Tree used to compile a query string on a Memex Project into an elasticsearch Query.
    # Used in MemexProjectItemQuery.
    #
    # EXAMPLE
    #
    #   context = Search::Memex::Context.new(viewer: current_user)
    #   query = Search::Memex::AST.create("is:issue is:open").compile(context:)
    #   Elastomer::Indexes::MemexProjectItems.new.search({ query: })
    class AST
      extend T::Sig
      extend Forwardable

      # Builds and returns the root node of the AST.
      sig { params(query: String).returns(AST) }
      def self.parse(query)
        parser_results = QueryParser.parse(query, normalizer: -> (q) { q.strip })

        children = T.let(qualifier_nodes(parser_results), T::Array[T.nilable(Node)])
        children << full_text_query_node(parser_results)
        children = children.compact

        new(root_node: Nodes::Root.new(children:))
      end

      sig { params(root_node: Nodes::Root).void }
      def initialize(root_node:)
        @root_node = root_node
      end

      # Compiles each node of the query into a hash representing the query to be used in MemexProjectItemQuery.
      #
      # example query: "is:issue,pr my full text search"
      #
      # example return value:
      # {
      #  :bool=>{
      #    :must_not=>[{:exists=>{:field=>"archived_at"}}],
      #    :filter=>[{:term=>{:memex_project_id=>{:value=>110}}}],
      #    :should=>[{:term=>{"content.type"=>{:value=>"Issue"}}}, {:term=>{"content.type"=>{:value=>"PullRequest"}}}],
      #    :minimum_should_match=>1},
      #    :must=>[{:match=>{:future_searchable_text=>"my full text search"}}]
      #   }
      # }
      sig { params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
      def compile(context)
        @root_node.compile(context)
      end

      sig { params(query_slug: Symbol).returns(T::Array[Nodes::Qualifier]) }
      def find_nodes_by_query_slug(query_slug)
        T.cast(
          @root_node.children.select { _1.is_a?(Nodes::Qualifier) && _1.query_slug == query_slug },
          T::Array[Nodes::Qualifier]
        )
      end

      sig { params(parser_results: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Array[T.nilable(Node)]) }
      private_class_method def self.qualifier_nodes(parser_results)
        parser_results.select { |r| r[:keyword] != :_ }.map do |qualifier|
          case qualifier[:keyword]
          when :is
            Search::Memex::Nodes::ContentQualifier.new(qualifier)
          when :has, :no
            Search::Memex::Nodes::FieldValuePresenceQualifier.new(qualifier)
          when :"last-updated"
            Search::Memex::Nodes::LastUpdatedQualifier.new(qualifier)
          when :updated
            Search::Memex::Nodes::UpdatedQualifier.new(qualifier)
          when :reason
            Search::Memex::Nodes::ReasonQualifier.new(qualifier)
          else # Any qualifier where the slug corresponds to a field name e.g. `assignees:`, `status:`
            Search::Memex::Nodes::FieldValueQualifier.new(qualifier)
          end
        end
      end

      sig { params(parser_results: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T.nilable(Node)) }
      private_class_method def self.full_text_query_node(parser_results)
        text_search_terms = parser_results.select { |r| r[:keyword] == :_ }.flat_map { |t| t[:values] }
        text_search_terms.any? ? Nodes::FullTextQuery.new(text_search_terms.join(" ")) : nil
      end
    end
  end
end
