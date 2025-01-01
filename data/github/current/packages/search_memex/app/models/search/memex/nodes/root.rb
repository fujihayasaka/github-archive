# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Used by AST to get the base scope (e.g., project, viewer) and items scope (archived, unarchived, all),
      # then compiles the child nodes representing the supplied query string.
      # Memex projects accept Qualifiers (e.g., "is:issue") and full text searches (e.g., "my issue title").
      class Root < Node
        extend T::Helpers

        sig { returns(T::Array[Node]) }
        attr_accessor :children

        sig { params(children: T::Array[Node]).void }
        def initialize(children:)
          @children = children
        end

        # Given the context,
        #   get the base scope (project, viewer) unless skip_project_scope
        #   get the items scope (archived, unarchived, all) unless skip_items_scope
        #   call compile on the children (qualifiers, full text query)
        #   merge the results into a single hash representing the query
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          if context.options.skip_items_scope
            items_filter = {}
          else
            items_scope = context.items_scope
            case items_scope
            when Search::Memex::Context::MemexProjectItemsScope::Archived
              items_filter = archived_items_filter
            when Search::Memex::Context::MemexProjectItemsScope::Unarchived
              items_filter = unarchived_items_filter
            when Search::Memex::Context::MemexProjectItemsScope::All
              items_filter = {}
            else
              T.absurd(items_scope)
            end
          end

          if context.options.skip_project_scope
            result = {}
          else
            result = very_deep_merge(base_memex_scope(context), items_filter)
          end

          compiled_nodes = @children.map { |node| node.compile_as_must_query(context) }.inject({}) do |query_hash_part, result|
            result.deep_merge(query_hash_part) do |_key, oldval, newval|
              if oldval.is_a?(Array) || newval.is_a?(Array)
                Array.wrap(oldval) + Array.wrap(newval)
              else
                newval
              end
            end
          end
          very_deep_merge(result, compiled_nodes)
        end

        sig { override.returns(String) }
        def query_string
          ""  # Empty string as a basic implementation
        end

        private

        sig { params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def base_memex_scope(context)
          {
            bool: {
              filter: [{ term: { memex_project_id: { value: context.memex_project.id } } }]
            }
          }
        end

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def archived_items_filter
          {
            bool: {
              filter: [{ exists: { field: :archived_at } }]
            }
          }
        end

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def unarchived_items_filter
          {
            bool: {
              must_not: [{ exists: { field: "archived_at" } }]
            }
          }
        end

        # Given two hashes, recursively merge them.
        # If the values for a given key are arrays in both hashes, merge the arrays.
        sig { params(hash_1: T::Hash[T.untyped, T.untyped], hash_2: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
        def very_deep_merge(hash_1, hash_2)
          hash_1.deep_merge(hash_2) do |_key, oldval, newval|
            if oldval.is_a?(Array) || newval.is_a?(Array)
              Array.wrap(oldval) + Array.wrap(newval)
            elsif oldval.is_a?(Hash) && newval.is_a?(Hash)
              very_deep_merge(oldval, newval)
            else
              newval
            end
          end
        end
      end
    end
  end
end
