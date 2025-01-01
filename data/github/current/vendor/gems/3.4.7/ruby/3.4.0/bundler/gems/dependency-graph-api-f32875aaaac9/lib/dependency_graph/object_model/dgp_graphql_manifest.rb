require_relative "base_graphql_manifest"
require_relative "dgp_graphql_dependency"
require "dependency-graph-platform/graphql_resolver_client"

module DependencyGraph::ObjectModel
  class DGPGraphqlManifest < BaseGraphqlManifest

    class << self
      attr_reader :dgp_graphql_client
    end

    # Use the same client for all instances of this class
    @dgp_graphql_client = DependencyGraphAPI::DependencyGraphPlatform::GraphQLResolverClient.new

    ROOT_PATH = "."

    def initialize(manifest)
      super(manifest.id, manifest.repository_id, manifest)
    end

    # Give a filename if it exists, otherwise return the manifest name. This is
    # a hack to show something meaningful in a web ui that doesn't understand
    # anything but files.
    def filename
      return @filename if defined?(@filename)
      @filename = @manifest.name
    end

    def path
      return @path if defined?(@path)

      if !@manifest.path.present? || @manifest.path.empty? || @manifest.path == ROOT_PATH
        @path = ""
      else
        @path = @manifest.path
      end

      @path
    end

    def name
      @manifest.name
    end

    def source
      "dgp"
    end

    # This method gets the dependencies from DGP using the class instance client
    def fetch_dependencies
      response = self.class.dgp_graphql_client.get_dependencies_for_manifest(repository_id: github_repository_id, manifest_id: id)

      if response.error.present?
        DependencyGraph.logger.error("Outbound call to dgp failed",
                                     "exception.message" => response.error.msg[..500])
        return Twirp::Error.internal("An unexpected error occurred during dgp dependencies retrieval")
      end

      include_package_url = ds_arbitrary_ecosystem_enabled?(@repository_id)
      response.data.dependencies.map do |dep|
        DependencyGraph::ObjectModel::DGPGraphqlDependency.new(dep, include_transitive_labels: true, include_package_url: include_package_url)
      end
    end
  end
end
