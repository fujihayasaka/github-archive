module DependencyGraph::ObjectModel::DependencyVulnerabilitiesHash
  # A common mechanishm for retrieving the vulnerabilities hash (keyed by dependency) for a set of manifests
  # manifests is an array of DependencyGraph::ObjectModel::AbstractManifests
  # return a hash:  { <dependency>: VulnerabilityVersionRange }
  def self.generate_hash(manifests)
    GitHub::Telemetry.tracer.in_span("load_vulnerabilities") do
      package_managers_by_dependency = generate_dependencies_by_package_manager_hash(manifests)
      vulnerabilities_hash_by_dependency = {}
      dependencies_by_manifest_type = {}
      package_managers_by_dependency.each do |dependency, package_manager|
        dependencies_by_manifest_type[package_manager] ||= []
        dependencies_by_manifest_type[package_manager].append(dependency)
      end

      dependencies_by_manifest_type.each do |package_manager, dependencies|
        dependencies.flatten!
        dependencies_by_name = dependencies.group_by { |dependency| dependency.full_package_name.downcase }
        names_to_look_for = dependencies_by_name.keys

        scoped_ranges = ::VulnerableVersionRange
                          .for_package_manager(package_manager)
                          .for_package(names_to_look_for)
                          .select(:id, :package_name, :version_range, :github_id)

        scoped_ranges.find_in_batches do |batch_of_ranges|
          batch_of_ranges.each do |range|
            vuln_for_package_name = range.package_name.downcase
            dependencies = dependencies_by_name[vuln_for_package_name]

            if dependencies.blank?
              DependencyGraph.logger.warn("Vulnerability range does not match expected package name",
                "gh.dependency_graph.package_name": vuln_for_package_name
              )
              next
            else
              dependencies.each do |dependency|
                vulnerabilities_hash_by_dependency[dependency] ||= []
                vulnerabilities_hash_by_dependency[dependency].push(range)
              end
            end
          end
        end
      end
      vulnerabilities_hash_by_dependency
    end
  end


  # Utility to generate a hash of dependencies by package manager.
  # manifests is an array of DependencyGraph::ObjectModel::AbstractManifests
  # return a hash:  { <Types::PackageManager> : <ObjectModel::AbstractDependency>[] }
  def self.generate_dependencies_by_package_manager_hash(manifests)
    package_manager_by_dependency = {}
    manifests.each do |manifest|
      manifest.dependencies.each do |dependency|
        package_manager_by_dependency[dependency] = dependency.package_manager
      end
    end

    package_manager_by_dependency
  end
end
