# typed: strict
# frozen_string_literal: true

module Repositories
  module Contents
    class Metadata
      sig { returns(T::Boolean) }
      attr_reader :empty_repository

      sig { returns T.nilable(String) }
      attr_reader :head_oid

      sig { returns T.nilable(String) }
      attr_reader :ref_name

      sig { returns T.nilable(String) }
      attr_reader :ref_commit_oid

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

      # Build a new instance of RepositoryContentMetadata.
      sig do
        params(
          empty_repository: T::Boolean,
          head_oid: T.nilable(String),
          ref_name: T.nilable(String),
          ref_commit_oid: T.nilable(String),
          root_tree_entry_oid: T.nilable(String),
          path_object_type: T.nilable(Symbol),
          path_object_oid: T.nilable(String),
          path_object_mode: T.nilable(Integer),
          path_object_size: T.nilable(Integer)
        ).void
      end
      def initialize(
        empty_repository: false,
        head_oid: nil,
        ref_name: nil,
        ref_commit_oid: nil,
        root_tree_entry_oid: nil,
        path_object_type: nil,
        path_object_oid: nil,
        path_object_mode: nil,
        path_object_size: nil
      )
        @empty_repository = empty_repository
        @head_oid = head_oid
        @ref_name = ref_name
        @ref_commit_oid = ref_commit_oid
        @root_tree_entry_oid = root_tree_entry_oid
        @path_object_type = path_object_type
        @path_object_oid = path_object_oid
        @path_object_mode = path_object_mode
        @path_object_size = path_object_size
      end

      EMPTY_REPOSITORY = T.let(Repositories::Contents::Metadata.new(empty_repository: true), Repositories::Contents::Metadata)

      # Returns true if the repository is empty.
      sig { returns T::Boolean }
      def empty_repository?
        empty_repository
      end

      # Returns true if the commit is not found.
      sig { returns T::Boolean }
      def commit_not_found?
        ref_commit_oid.blank?
      end

      # Returns true if the tree is not found.
      sig { returns T::Boolean }
      def tree_not_found?
        root_tree_entry_oid.blank?
      end

      # Returns true if the object is not found.
      sig { returns T::Boolean }
      def object_not_found?
        path_object_oid.blank?
      end

      # Returns true if the object is a tree.
      sig { returns T::Boolean }
      def tree?
        return false if object_not_found?

        path_object_type == :tree
      end

      # Returns true if the object is a submodule.
      sig { returns T::Boolean }
      def submodule?
        return false if object_not_found?

        path_object_type == :submodule
      end

      # Returns true if the object is a blob.
      sig { returns T::Boolean }
      def blob?
        return false if object_not_found?

        path_object_type == :blob
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(self.class)

        empty_repository == other.empty_repository &&
          head_oid == other.head_oid &&
          ref_name == other.ref_name &&
          ref_commit_oid == other.ref_commit_oid &&
          root_tree_entry_oid == other.root_tree_entry_oid &&
          path_object_type == other.path_object_type &&
          path_object_oid == other.path_object_oid &&
          path_object_mode == other.path_object_mode &&
          path_object_size == other.path_object_size
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          empty_repository: empty_repository,
          head_oid: head_oid,
          ref_name: ref_name,
          ref_commit_oid: ref_commit_oid,
          root_tree_entry_oid: root_tree_entry_oid,
          path_object_type: path_object_type,
          path_object_oid: path_object_oid,
          path_object_mode: path_object_mode,
          path_object_size: path_object_size
        }
      end
    end
  end
end
