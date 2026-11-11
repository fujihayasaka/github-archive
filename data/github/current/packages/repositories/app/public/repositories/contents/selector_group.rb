# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    class SelectorGroup
      extend T::Helpers

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

      sig { returns T.nilable(Integer) }
      attr_reader :path_object_mode

      sig { returns T.nilable(Integer) }
      attr_reader :path_object_size

      # Returns a new instance of a by ref selector object.
      sig { params(ref_name: String, qualified_ref_name: String, path: T.nilable(String)).void }
      def initialize(ref_name:, qualified_ref_name:, path:)
        @ref_name = T.let(ref_name, String)
        @qualified_ref_name = T.let(qualified_ref_name, String)
        @path = T.let(path, T.nilable(String))

        @commit_oid = T.let(nil, T.nilable(String))
        @root_tree_entry_oid = T.let(nil, T.nilable(String))
        @path_object_type = T.let(nil, T.nilable(Symbol))
        @path_object_oid = T.let(nil, T.nilable(String))
        @path_object_mode = T.let(nil, T.nilable(Integer))
        @path_object_size = T.let(nil, T.nilable(Integer))
      end
      # Returns the selectors to resolve the commit, root tree entry and path object.
      sig { returns(T::Array[T.untyped]) }
      def selectors
        selectors = [commit_selector, root_tree_entry_selector]
        selectors << T.must(path_object_selector) if !path.nil?
        selectors
      end

      # Consumes the resolved objects and assigns the commit, root tree entry and path object.
      sig do
        params(
          resolved_objects: T::Array[GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem],
          missing_path_fallback: T.proc.params(commit_oid: String, path: String).returns(T.nilable([Symbol, String, Integer, Integer]))
        ).void
      end
      def parse_resolved_objects(resolved_objects:, missing_path_fallback:)
        commit_object, root_tree_entry_object, path_object = resolved_objects

        @commit_oid = commit_object&.error.present? ? nil : T.must(commit_object&.object&.oid&.id)
        @root_tree_entry_oid = root_tree_entry_object&.error.present? ? nil : T.must(root_tree_entry_object&.object&.oid&.id)

        return if path_object.nil?

        # Try the missing path fallback if is a commit object && the mode is not a Submodule.
        # ResolveObjects has two issues the underlying git cat-file bug where
        # - it can return a commit object if a tree entry path is provided that happens to include (-g<sha>) syntax in the path name.
        # - it can return missing error when the ref name has an { and a path is provided
        if path && @commit_oid &&
          (
            (path_object.error == "missing" && ref_name.include?("{")) ||
            (path_object.object&.type == :TYPE_COMMIT && path_object.object&.mode != Repositories::Domain::Contents::SUBMODULE_MODE)
          )
          result = missing_path_fallback.call(T.must(commit_oid), T.must(path))
          if result.present?
            git_object_type, oid, mode, size = result
            set_path_object(git_object_type, oid, mode, size)
          end
          return
        end

        return if path_object.error.present?

        set_path_object(
          T.must(path_object.object&.type),
          T.must(path_object.object&.oid&.id),
          T.must(path_object.object).mode,
          T.must(path_object.object).size
        )
      end

      sig { params(git_object_type:  T.any(Symbol, Integer), oid: String, mode: Integer, size: Integer).void }
      def set_path_object(git_object_type, oid, mode, size)
        @path_object_type = Repositories::Contents::ContentHelpers.git_contents_type(git_object_type)
        @path_object_oid = oid
        @path_object_mode = mode
        @path_object_size = size
      end

      # Returns true if the resolution of all objects succeeded, false otherwise.
      sig { returns(T::Boolean) }
      def succeeded?
        return false unless commit_oid.present?
        return false unless root_tree_entry_oid.present?
        return path_object_type.present? && path_object_oid.present? if !path.nil?

        true
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
      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def path_object_selector
        { by_treeish_and_path: { treeish: { revision: { name: qualified_ref_name.b } }, path: { name: T.must(path).b } } }
      end
    end
  end
end
