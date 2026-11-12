require_relative "dgp_client"

module DependencyGraphAPI
  module DependencyGraphPlatform
    class GraphQLResolverClient
      include DGPClient

      def initialize(use_json: false)
        @use_json = use_json
      end

      # repository_has_manifests:   check whether a repository has manifests in DGP.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      #
      def repository_has_manifests(repository_id:)
        request = Github::DependencyGraphPlatform::Graphql::V1::RepositoryHasManifestsRequest.new(
          repository_id: repository_id
        )
        client.repository_has_manifests(request)
      end

      # get_manifests_for_repository:   retrieve manifests from DGP by given repository_id
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      # manifest_ids: Optional list of manifest IDs to fetch from DGP
      # with_dependencies: Optional filter used to only include manifests with dependencies.
      # ecosystems: Optional list of ecosystems to filter by
      #
      def get_manifests_for_repository(repository_id:, manifest_ids:, with_dependencies:, ecosystems:)
        request = Github::DependencyGraphPlatform::Graphql::V1::GetManifestsForRepositoryRequest.new(
          repository_id: repository_id,
          manifest_ids: manifest_ids,
          with_dependencies: with_dependencies,
          ecosystems: ecosystems
        )
        client.get_manifests_for_repository(request)
      end

      # get_dependencies_for_manifest:   retrieve dependencies from DGP by given repository_id and manifest_id
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      # manifest_id: Manifest ID (unsigned nonzero integer)
      #
      def get_dependencies_for_manifest(repository_id:, manifest_id:)
        request = Github::DependencyGraphPlatform::Graphql::V1::GetDependenciesForManifestRequest.new(
          repository_id: repository_id,
          manifest_id: manifest_id
        )
        client.get_dependencies_for_manifest(request)
      end

      def client
        content_type = @use_json ? Twirp::Encoding::JSON : nil
        @client ||= Github::DependencyGraphPlatform::Graphql::V1::GraphQLResolverClient.new(connection, content_type: content_type)
      end
    end
  end
end
