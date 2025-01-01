require_relative "dgp_client"

module DependencyGraphAPI
  module DependencyGraphPlatform
    class RepoInsightsClient
      include DGPClient

      def initialize(use_json: false)
        @use_json = use_json
      end

      # get_dependencies_for_repository:   retrieve dependencies from DGP by given repository_id
      #                                    and optional query, pagination, and vulnerability filter.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      #
      def get_dependencies_for_repository(repository_id:, pagination:, package_name_filter:, vulnerability_filter:, vulnerable_version_ranges:, relationship_filter:, ecosystem_filter:)
        request = Github::DependencyGraphPlatform::RepoInsights::V1::GetDependenciesForRepositoryRequest.new(
          repository_id: repository_id,
          pagination: pagination,
          package_name_filter: package_name_filter,
          vulnerability_filter: vulnerability_filter,
          vulnerable_version_ranges: vulnerable_version_ranges,
          relationship_filter: relationship_filter,
          ecosystem_filter: ecosystem_filter
        )
        client.get_dependencies_for_repository(request)
      end

      # get_root_ancestors_for_dependencies:   retrieve root direct dependencies from DGP by given repository_id
      #                                    and list of transitive dependency_ids.
      #
      # repository_id: GitHub repository ID (unsigned nonzero integer)
      # dependency_ids: List of dependency IDs i.e. T::Array[Integer]
      #
      def get_root_ancestors_for_dependencies(repository_id:, dependency_ids:)
        request = Github::DependencyGraphPlatform::RepoInsights::V1::GetRootAncestorsForDependenciesRequest.new(
          repository_id: repository_id,
          dependency_ids: dependency_ids
        )
        client.get_root_ancestors_for_dependencies(request)
      end

      def client
        content_type = @use_json ? Twirp::Encoding::JSON : nil
        @client ||= Github::DependencyGraphPlatform::RepoInsights::V1::RepoInsightsAPIClient.new(connection, content_type: content_type)
      end
    end
  end
end
