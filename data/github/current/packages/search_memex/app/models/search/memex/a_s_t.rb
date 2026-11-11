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
      extend Forwardable
      include Search::Memex::Nodes::DependenciesValueHelpers

      # Builds and returns the root node of the AST.
      sig { params(query: T.nilable(String), context: T.nilable(Search::Memex::Context), enable_groups: T::Boolean).returns(AST) }
      def self.parse(query, context: nil, enable_groups: false)
        parser_results = QueryParser.parse(query, context:, enable_groups:)

        children = T.let(qualifier_nodes_with_or_groups(parser_results), T::Array[T.nilable(Node)])
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

      # Returns true if the parsed query contains any sub-issue filter nodes.
      sig { returns(T::Boolean) }
      def has_sub_issue_filters?
        @root_node.has_sub_issue_filters?
      end

      sig { params(query_slug: Symbol).returns(T::Array[Nodes::Qualifier]) }
      def find_nodes_by_query_slug(query_slug)
        collect_qualifiers_by_slug(@root_node.children, query_slug)
      end

      sig { params(query_slug: Symbol).returns(T::Array[T::Array[Nodes::Qualifier]]) }
      def find_node_groups_by_query_slug(query_slug)
        collect_qualifier_groups_by_slug(@root_node.children, query_slug)
      end

      private

      # Recursively collects Qualifier nodes matching a given slug from a tree of nodes,
      # descending into OrGroup and ParenGroup children.
      sig { params(nodes: T::Array[Node], query_slug: Symbol).returns(T::Array[Nodes::Qualifier]) }
      def collect_qualifiers_by_slug(nodes, query_slug)
        results = T.let([], T::Array[Nodes::Qualifier])
        nodes.each do |node|
          case node
          when Nodes::Qualifier
            results << node if node.query_slug == query_slug && !node.sub_issue_filter?
          when Nodes::OrGroup
            node.or_segments.each do |segment|
              results.concat(collect_qualifiers_by_slug(segment, query_slug))
            end
          when Nodes::ParenGroup
            results.concat(collect_qualifiers_by_slug(node.children, query_slug))
          end
        end
        results
      end

      sig { params(nodes: T::Array[Node], query_slug: Symbol).returns(T::Array[T::Array[Nodes::Qualifier]]) }
      def collect_qualifier_groups_by_slug(nodes, query_slug)
        branches = T.let([[]], T::Array[T::Array[Nodes::Qualifier]])

        nodes.each do |node|
          node_branches = collect_qualifier_groups_for_node(node, query_slug)
          branches = branches.each_with_object(T.let([], T::Array[T::Array[Nodes::Qualifier]])) do |branch, result|
            node_branches.each do |node_branch|
              result << branch + node_branch
            end
          end
        end

        branches
      end

      sig { params(node: Node, query_slug: Symbol).returns(T::Array[T::Array[Nodes::Qualifier]]) }
      def collect_qualifier_groups_for_node(node, query_slug)
        case node
        when Nodes::Qualifier
          node.query_slug == query_slug && !node.sub_issue_filter? ? [[node]] : [[]]
        when Nodes::OrGroup
          node.or_segments.flat_map { |segment| collect_qualifier_groups_by_slug(segment, query_slug) }
        when Nodes::ParenGroup
          collect_qualifier_groups_by_slug(node.children, query_slug)
        else
          [[]]
        end
      end

      sig do params(
        parser_results: T::Array[T::Hash[T.untyped, T.untyped]],
      ).returns(T::Array[Node])
      end
      private_class_method def self.qualifier_nodes_with_or_groups(parser_results)
        # Separate OR markers from qualifier results (also exclude AND markers and free text :_)
        qualifier_results = parser_results.reject { |r| r[:keyword] == :_ }

        # Split the results into segments separated by OR markers.
        # Each segment is a list of qualifier results that are ANDed together.
        # A segment item may be either a raw qualifier hash or a pre-built ParenGroup node.
        or_segments = T.let([], T::Array[T::Array[T.untyped]])
        current_segment = T.let([], T::Array[T.untyped])

        qualifier_results.each do |result|
          if result[:keyword] == :OR
            or_segments << current_segment
            current_segment = []
          elsif result[:keyword] == :AND
            # AND is the default: treat as a no-op marker, keep current segment
          elsif result[:keyword] == :GROUP
            # Recursively process the paren group's children into a ParenGroup node.
            children_results = T.cast(result[:children], T::Array[T::Hash[T.untyped, T.untyped]])
            group_children = qualifier_nodes_with_or_groups(children_results)
            current_segment << Nodes::ParenGroup.new(children: group_children) unless group_children.empty?
          else
            current_segment << result
          end
        end
        or_segments << current_segment

        non_empty_segments = or_segments.reject(&:empty?)

        if non_empty_segments.length <= 1
          # No OR operators; build nodes as before
          build_segment_nodes(non_empty_segments.first || [])
        else
          # Multiple OR segments; wrap in a single OrGroup node
          segment_nodes = non_empty_segments.map { |segment| build_segment_nodes(segment) }
          [Nodes::OrGroup.new(or_segments: segment_nodes)]
        end
      end

      # Builds Node objects from a segment whose items may be either raw qualifier hashes
      # or pre-built Node objects (e.g. ParenGroup created during GROUP processing).
      sig { params(segment: T::Array[T.untyped]).returns(T::Array[Node]) }
      private_class_method def self.build_segment_nodes(segment)
        segment.filter_map do |item|
          if item.is_a?(Node)
            item
          else
            build_node_from_qualifier(T.cast(item, T::Hash[T.untyped, T.untyped]))
          end
        end
      end

      # Builds a single Node from a raw qualifier hash.
      sig { params(qualifier: T::Hash[T.untyped, T.untyped]).returns(Node) }
      private_class_method def self.build_node_from_qualifier(qualifier)
        case qualifier[:keyword]
        when :is
          Nodes::ContentQualifier.new(qualifier)
        when :has, :no
          Nodes::FieldValuePresenceQualifier.new(qualifier)
        when :"last-updated"
          Nodes::LastUpdatedQualifier.new(qualifier)
        when :updated
          Nodes::FieldValueQualifier.new(qualifier)
        when :reason
          Nodes::ReasonQualifier.new(qualifier)
        when :reviews
          if FeatureFlag.vexi.enabled?(:memex_reviews_qualifier, default: false)
            Nodes::ReviewsQualifier.new(qualifier)
          else
            Nodes::FieldValueQualifier.new(qualifier)
          end
        when :state
          Nodes::StateQualifier.new(qualifier)
        when *DEPENDENCIES_FIELDS.map(&:to_sym)
          Nodes::DependenciesQualifier.new(qualifier)
        else # Any qualifier where the slug corresponds to a field name e.g. `assignees:`, `status:`
          Nodes::FieldValueQualifier.new(qualifier)
        end
      end

      sig do params(
        parser_results: T::Array[T::Hash[T.untyped, T.untyped]],
      ).returns(T::Array[Node])
      end
      private_class_method def self.qualifier_nodes(parser_results)
        build_segment_nodes(parser_results)
      end

      sig { params(parser_results: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T.nilable(Node)) }
      private_class_method def self.full_text_query_node(parser_results)
        text_search_terms = parser_results.select { |r| r[:keyword] == :_ }.flat_map { |t| t[:values] }
        text_search_terms.any? ? Nodes::FullTextQuery.new(text_search_terms.join(" ")) : nil
      end
    end
  end
end
