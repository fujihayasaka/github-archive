module API
  module Types
    class Manifest < Types::BaseObject
      description "A dependency manifest"

      implements GraphQL::Types::Relay::Node

      global_id_field :id

      field :repository_id, Integer, method: :github_repository_id, null: false
      field :manifest_type, String, null: false
      field :filename, String, null: false
      field :path, String, null: false
      field :is_vendored, Boolean, method: :vendored?, null: false
      field :source, String, null: false
      field :snapshot_id, Integer, null: true
      field :snapshot_detector_name, String, null: true
      field :snapshot_scanned, String, null: true
      field :manifest_name, String, null: true

      def source
        if object.respond_to?(:source)
          object.source
        else
          "dependency graph"
        end
      end

      def manifest_name
        return object.name if object.is_a?(DependencyGraph::ObjectModel::BaseGraphqlManifest)

        nil
      end

      def snapshot_id
        return object.snapshot_id if object.is_a?(DependencyGraph::ObjectModel::DSGraphqlManifest)

        nil
      end

      def snapshot_detector_name
        return object.snapshot_detector_name if object.is_a?(DependencyGraph::ObjectModel::DSGraphqlManifest)

        nil
      end

      def snapshot_scanned
        return object.snapshot_scanned if object.is_a?(DependencyGraph::ObjectModel::DSGraphqlManifest)

        nil
      end

      field :dependencies, Connections::Dependencies, max_page_size: 250, null: true, connection: true do
        argument :prefer, [String, null: true], "A list of package names that will be returned at the top", required: false
      end

      def dependencies(**args)
        Queries::DependenciesQuery.new(
          dependent: object,
          prefer: args[:prefer]
        ).dependencies
      end
    end
  end
end
