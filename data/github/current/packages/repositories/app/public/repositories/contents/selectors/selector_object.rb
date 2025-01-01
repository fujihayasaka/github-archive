# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    module Selectors
      class SelectorObject
        extend T::Helpers

        abstract!

        sig { returns(Symbol) }
        attr_reader :ref_type

        sig { returns(String) }
        attr_reader :ref_name

        sig { returns(String) }
        attr_reader :qualified_ref_name

        sig { returns(T.nilable(String)) }
        attr_reader :path

        sig { returns T.nilable(String) }
        attr_reader :commit_oid

        sig { returns T.nilable(String) }
        attr_reader :root_tree_entry_oid

        sig { returns T.nilable(Symbol) }
        attr_reader :path_object_type

        sig { returns T.nilable(String) }
        attr_reader :path_object_oid

        # Returns a new instance of a by ref selector object.
        sig { params(ref_type: Symbol, ref_name: String, qualified_ref_name: String, path: T.nilable(String)).void }
        def initialize(ref_type:, ref_name:, qualified_ref_name:, path:)
          @ref_type = T.let(ref_type, Symbol)
          @ref_name = T.let(ref_name, String)
          @qualified_ref_name = T.let(qualified_ref_name, String)
          @path = T.let(path, T.nilable(String))
          # @commit_object = T.let(nil, T.nilable(GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem))
          # @root_tree_entry_object = T.let(nil, T.nilable(GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem))
          # @path_object = T.let(nil, T.nilable(GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem))

          @commit_oid = T.let(nil, T.nilable(String))
          @root_tree_entry_oid = T.let(nil, T.nilable(String))
          @path_object_type = T.let(nil, T.nilable(Symbol))
          @path_object_oid = T.let(nil, T.nilable(String))
          @selectors_count = T.let(0, Integer)
        end

        # Returns the selectors to resolve the commit, root tree entry and path object.
        sig { returns(T::Array[T.untyped]) }
        def selectors
          selectors = [
            commit_selector,
            root_tree_entry_selector,
            path_object_selector # nil if path.blank?
          ].compact

          # We want to keep track of the number of selectors to consume the resolved objects
          @selectors_count = selectors.count

          selectors
        end

        # Consumes the resolved objects and assigns the commit, root tree entry and path object.
        sig do
          params(
            resolved_objects: T::Array[GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem],
            try_submodule_fallback: T.proc.params(commit_oid: String, path: String).returns(T.nilable(String))
          ).void
        end
        def parse_resolved_objects(resolved_objects:, try_submodule_fallback:)
          commit_object, root_tree_entry_object, path_object = resolved_objects.shift(@selectors_count)

          @commit_oid = commit_object&.error.present? ? nil : T.must(T.must(T.must(commit_object).object).oid).id
          @root_tree_entry_oid = root_tree_entry_object&.error.present? ? nil : T.must(T.must(T.must(root_tree_entry_object).object).oid).id

          return if path_object.nil?

          if @commit_oid && path_object.error.present? && path_object.error == "missing"
            submodule_oid = try_submodule_fallback.call(T.must(commit_oid), T.must(path))
            if submodule_oid.present?
              @path_object_type = :submodule
              @path_object_oid = submodule_oid
              return
            end
          end

          return if path_object.error.present?

          path_object_oid = T.must(T.must(path_object.object).oid).id
          path_object_type_raw = T.must(path_object.object).type

          path_object_type = case path_object_type_raw
          when :TYPE_TREE
            :tree
          when :TYPE_BLOB
            :blob
          when :TYPE_COMMIT
            :submodule
          else
            raise "unexpected object type: #{path_object_type_raw}"
          end

          @path_object_type = path_object_type
          @path_object_oid = path_object_oid
        end

        # Returns true if the resolution of all objects succeeded, false otherwise.
        sig { returns(T::Boolean) }
        def succeeded?
          return false unless commit_oid.present?
          return false unless root_tree_entry_oid.present?
          return true if path.blank?

          path_object_type.present? && path_object_oid.present?
        end

        # Returns the commit selector to resolve the commit object.
        sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
        def commit_selector
          { by_name: { name: "#{qualified_ref_name}^{commit}".b } }
        end

        # Returns the root tree entry selector to resolve the root tree entry object.
        sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
        def root_tree_entry_selector
          { by_name: { name: "#{qualified_ref_name}^{tree}".b } }
        end

        # Returns the path object selector to resolve the path object.
        sig { abstract.returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def path_object_selector; end

      end
    end
  end
end
