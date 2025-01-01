require "securerandom"
require "dependency_graph/sbom/generator"
require "dependency_graph/sbom/dependency"
require "dependency_graph/sbom/spdx/spdx_document"
require "dependency_graph/sbom/spdx/spdx_package"
require "monolith/repositories"

module DependencyGraph
  module SBOM
    module SPDX
      class Generator < DependencyGraph::SBOM::Generator
        def generate(repository_id:, repository_name:, namespace_base:, repository_license: "")
          DependencyGraph.logger.info("Starting SPDX generation")

          # This fetches the latest dependencies from manifests: the state of the graph at the HEAD commit
          # (as far as we know)
          snapshot_dependencies, snapshot_detectors, manifest_file_paths = get_sbom_data_from_snapshots(repository_id: repository_id)
          Instrument.count("sbom.dependencies.count", snapshot_dependencies.count, dependency_source: :snapshots)
          db_dependencies = get_dependencies_from_database(repository_id: repository_id, exclude_superseded_manifests: true, exclude_file_paths: manifest_file_paths)
          Instrument.count("sbom.dependencies.count", db_dependencies.count, dependency_source: :database)

          snapshot_detector_tools = snapshot_detectors.map do |detector|
            "Tool: #{detector}"
          end

          dependencies = db_dependencies.concat(snapshot_dependencies)
          packages = dependencies.map { |dep| SPDXPackage.new(dependency: dep) }.uniq(&:purl)

          Instrument.count("sbom.unique_dependencies.count", packages.count)

          doc = SPDXDocument.from_repository(
            repository_name: repository_name,
            repository_license: repository_license,
            namespace_base: namespace_base,
            packages: packages,
            additional_tools: snapshot_detector_tools
          )
          doc.generate
        end
      end
    end
  end
end
