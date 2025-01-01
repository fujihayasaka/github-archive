# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  autoload :AlertableDependent, "dependency_graph_platform/alertable_dependent"
  autoload :AlertableDependency, "dependency_graph_platform/alertable_dependency"
  autoload :AlertableManifest, "dependency_graph_platform/alertable_manifest"
  autoload :AllRepositoriesWithVersionRangeQuery, "dependency_graph_platform/all_repositories_with_version_range_query"
  autoload :Twirp, "dependency_graph_platform/twirp"
end
