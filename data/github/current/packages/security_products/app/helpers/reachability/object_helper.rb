# typed: true
# frozen_string_literal: true

require "dependency-graph-platform-proto"

module Reachability
  module ObjectHelper
    extend self

    sig { params(twirp_response: Github::DependencyGraphPlatform::Reachability::V1::GetDependenciesResponse, only_vulnerable_functions: T::Boolean).returns(Reachability::Object) }
    def create_reachability_object(twirp_response, only_vulnerable_functions: false)
      reachability_object = Reachability::Object.new

      projects = {}
      package_versions = Hash.new { |h, k| h[k] = {} }

      twirp_response.manifests.each do |manifest|
        m = create_manifest_data(manifest)
        project_key = [manifest.ecosystem, manifest.path].join(":")

        if projects.key?(project_key)
          projects[project_key].manifests.append(m[:manifest])
          projects[project_key].graph.merge!(m[:nodes])
        else
          projects[project_key] = Object::Project.new(
            ecosystem: manifest.ecosystem.to_s,
            manifests: [m[:manifest]],
            graph: m[:nodes]
          )
        end

        package_versions[manifest.ecosystem].merge!(m[:package_versions])
      end

      vulns_start_time = GitHub::Dogstats.monotonic_time
      vulnerabilities = fetch_vulnerabilities(package_versions, only_vulnerable_functions:)
      send_vuln_stats(start_time: vulns_start_time, vuln_count: vulnerabilities.length, only_vulnerable_functions:)

      reachability_object.vulnerabilities = vulnerabilities
      reachability_object.projects = projects.values

      reachability_object
    end

    sig { params(manifest: Github::DependencyGraphPlatform::Types::V1::Manifest).returns(T::Hash[Symbol, T.untyped]) }
    def create_manifest_data(manifest)
      path, filename = manifest.path, manifest.filename
      d = create_dependencies_data(manifest.dependencies.to_a)

      data = {
        manifest: Object::Manifest.new(
          source_location: [path, "/", filename].join,
          dependencies: d[:direct_edges],
        ),
        nodes: d[:nodes],
        package_versions: d[:package_versions]
      }

      data
    end

    sig { params(dependencies: T::Array[Github::DependencyGraphPlatform::Types::V1::Dependency]).returns(T::Hash[Symbol, T.untyped]) }
    def create_dependencies_data(dependencies)
      data = {
        direct_edges: [],
        nodes: {},
        package_versions: Hash.new { |h, k| h[k] = [] }
      }

      dependencies.each do |dep|
        id = dep.id
        dev = dep.scope == :SCOPE_DEVELOPMENT

        data[:nodes][id] = Object::DependencyNode.new(
          package_name: dep.name,
          version: dep.version,
          dependencies: dep.transitive_dependencies.map do |child|
            Object::DependencyEdge.new(
              node: child.id,
              dev: dev
            )
          end
        )

        data[:package_versions][dep.name].push(dep.version)

        if dep.relationship == :RELATIONSHIP_DIRECT
          data[:direct_edges].push(Object::DependencyEdge.new(
            node: id,
            dev: dev
          ))
        end
      end

      data
    end

    # Expects a hash organized by ecosystem, each ecosystem having a hash that consists
    # of individual packages in the whole object and all versions identified.
    # { <ecosystem>: { <package_name>: [<version>, ...], <package_name>: [<version>, ...], ... } }
    sig { params(package_versions_hash: T::Hash[String, T::Hash[String, T::Array[T.untyped]]], only_vulnerable_functions: T::Boolean).returns(T::Array[T.untyped]) }
    def fetch_vulnerabilities(package_versions_hash, only_vulnerable_functions: false)
      vulns = [] # TODO - consider implementing caching if perf isn't sufficient?

      package_versions_hash.each do |ecosystem, package_versions|
        ecosystem_str = ecosystem.to_s.split("_").last&.downcase
        packages = package_versions.keys
        packages.in_groups_of(50, false) do |batch|
          Vulnerability.disclosed.where(vulnerable_version_ranges: { ecosystem: ecosystem_str, affects: batch }).find_each(batch_size: 50) do |vuln|
            ranges = vuln.vulnerable_version_ranges
            ranges = ranges.select(&:affected_functions?) if only_vulnerable_functions
            if vuln.affects_package_versions?(package_versions, ranges)
              vulns.push(Object::Advisory.new(
                ghsa_id: vuln.ghsa_id,
                ranges: ranges.to_a
              ))
            end
          end
        end
      end

      vulns
    end

    def send_vuln_stats(start_time:, vuln_count:, only_vulnerable_functions:)
      GitHub.dogstats.count("reachability.fetch_vulnerabilities.count", vuln_count, tags: ["only_vulnerable_functions:#{only_vulnerable_functions}"])
      GitHub.dogstats.timing_since("reachability.fetch_vulnerabilities.time", start_time, tags: ["only_vulnerable_functions:#{only_vulnerable_functions}"])
    end
  end
end
