# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Contents < GH::Domain::Base

      EMPTY_REPOSITORY_SELECTOR = T.let({ by_name: { name: "HEAD".b } }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

      # Returns the metadata of a repository content by the given ref and path.
      # It will return the default branch content if the ref is not provided.
      # It will return the root directory content if the path is not provided.
      sig do
        params(
          repository: IRepository,
          ref: T.nilable(String),
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def metadata_by_ref_and_path(repository:, ref: nil, path: nil)
        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast
        # Paths like /folder/file.txt will become folder/file.txt
        # All the paths should be relative to the root of the repository.
        path = path.delete_prefix("/") if path.present?

        ref_selector_objects = Repositories::Contents::Selectors.build(repository:, ref:, path:)

        resolve_objects_by(repository:, ref_selector_objects:, path:)
      end

      private

      # Returns the metadata of a repository content by the given:
      # - ref_types: represents the ref types for which we will create the resolve object selectors.
      # - repository: the repository in which the content is located.
      # - ref: the ref in which it will try to resolve the content.
      # - path_string: the path if we want to resolve a specific file or directory. Otherwise, it will resolve the root directory content.
      sig do
        params(
          repository: Repository,
          ref_selector_objects: T::Array[Repositories::Contents::Selectors::SelectorObject],
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def resolve_objects_by(repository:, ref_selector_objects:, path:)
        # The resolved objects will be in the order of the selectors.
        # To make easier the processing of the resolved objects, we will add an empty repository selector at the beginning.
        selectors = [EMPTY_REPOSITORY_SELECTOR] + ref_selector_objects.flat_map(&:selectors)

        resolved_objects = repository.spokes_api.resolve_objects_by(selectors).items.to_a

        # Since the EMPTY_REPOSITORY_SELECTOR is the first selector
        # we can process it first.
        empty_repository_resolved_item = resolved_objects.shift

        selected_object = process_resolved_objects(repository, ref_selector_objects, resolved_objects)

        build_metadata(
          repository:,
          head_resolved_item: empty_repository_resolved_item,
          ref_selector_object: selected_object,
          path: path
        )
      end

      sig do
        params(
          repository: Repository,
          ref_selector_objects: T::Array[Repositories::Contents::Selectors::SelectorObject],
          resolved_objects: T::Array[GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem]
        ).returns(Repositories::Contents::Selectors::SelectorObject)
      end
      def process_resolved_objects(repository, ref_selector_objects, resolved_objects)
        selector_resolved_objects = ref_selector_objects.map do |selector_object|
          selector_object.parse_resolved_objects(
            resolved_objects:,
            try_submodule_fallback: -> (commit_oid, path) {
              try_submodule(repository: repository, commit_oid:, path:)
            }
          )
          selector_object
        end

        # Find the first resolved object without error.
        selected_object = selector_resolved_objects.detect { |selector| selector.succeeded? }

        return selected_object if selected_object.present?

        # If all resolved objects have errors, we will return the last one.
        T.must(selector_resolved_objects.last)
      end

      # Returns the metadata of a repository content by the given resolved objects.
      sig do
        params(
          repository: Repository,
          head_resolved_item: GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem,
          ref_selector_object: Repositories::Contents::Selectors::SelectorObject,
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def build_metadata(repository:, # rubocop:disable Metrics/MethodLength
        head_resolved_item:,
        ref_selector_object:,
        path: nil
      )

        ref_name = ref_selector_object.ref_name
        ref_type = ref_selector_object.ref_type

        if head_resolved_item.error.present?
          return Repositories::Contents::Metadata::EMPTY_REPOSITORY
        end

        head_oid = T.must(T.must(head_resolved_item.object).oid).id

        if ref_selector_object.commit_oid.nil?
          return Repositories::Contents::Metadata.new(head_oid:)
        end

        ref_commit_oid = ref_selector_object.commit_oid

        if ref_selector_object.root_tree_entry_oid.nil?
          return Repositories::Contents::Metadata.new(
            head_oid:,
            ref_name:,
            ref_type:,
            ref_commit_oid:
          )
        end

        root_tree_entry_oid = ref_selector_object.root_tree_entry_oid

        if ref_selector_object.path_object_type.nil?
          if path.blank?
            # We are resolving the root directory
            return Repositories::Contents::Metadata.new(
              head_oid:,
              ref_name:,
              ref_type:,
              ref_commit_oid:,
              root_tree_entry_oid:,
              path_object_type: :tree,
              path_object_oid: root_tree_entry_oid
            )
          end
          return Repositories::Contents::Metadata.new(
            head_oid:,
            ref_name:,
            ref_type:,
            ref_commit_oid:,
            root_tree_entry_oid:
          )
        end

        Repositories::Contents::Metadata.new(
          head_oid:,
          ref_name:,
          ref_type:,
          ref_commit_oid:,
          root_tree_entry_oid:,
          path_object_type: ref_selector_object.path_object_type,
          path_object_oid: ref_selector_object.path_object_oid
        )
      end

      sig { params(repository: Repository, commit_oid: String, path: String).returns(T.nilable(String)) }
      def try_submodule(repository:, commit_oid:, path:)
        repository.spokes_api.read_tree_entry_oid(oid: commit_oid, path: path, type: "commit")
      rescue => e # rubocop:disable Lint/GenericRescue
        nil
      end
    end
  end
end
