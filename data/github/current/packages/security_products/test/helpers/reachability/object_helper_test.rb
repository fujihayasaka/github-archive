# typed: true
# frozen_string_literal: true

require "test_helper"
require "dependency-graph-platform-proto"

class ObjectHelperTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @vuln1 = create(:vulnerability, ecosystem: "npm", with_ranges: 0)
    @vvr1 = create(:vulnerable_version_range,
                  ecosystem: "npm",
                  affects: "dependency_1",
                  requirements: "< 2.4.0",
                  vulnerability: @vuln1
                 )
    @vuln2 = create(:vulnerability, ecosystem: "npm", with_ranges: 0)
    @vvr2  = create(:vulnerable_version_range,
                   ecosystem: "npm",
                   affects: "dependency_1",
                   requirements: ">= 3.1, < 3.4",
                   vulnerability: @vuln2
                  )
    @vuln3 = create(:vulnerability, ecosystem: "npm", with_ranges: 0)
    @vvr3  = create(:vulnerable_version_range,
                   ecosystem: "npm",
                   affects: "transitive_dependency_2",
                   requirements: ">= 1.0.0, < 1.0.3",
                   affected_functions: ["vuln_func"],
                   vulnerability: @vuln3
                  )

    @manifest_1 = generate_manifest(
      filename: "package.json",
      ecosystem: :ECOSYSTEM_NPM,
      direct_deps_count: 2,
      create_transitives: true
    ).freeze

    @twirp_response = twirp_response_class.new(
        repository_id: 1,
        commit_oid: "1234av",
        status: :JOB_STATUS_COMPLETED,
        manifests: [@manifest_1]
    ).freeze
  end

  def twirp_response_class
    Github::DependencyGraphPlatform::Reachability::V1::GetDependenciesResponse
  end

  context "object creation" do
    test "can create a reachability object" do
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)

      assert obj.is_a?(Reachability::Object)
      assert_equal 1, obj.projects.length

      project = obj.projects.first
      manifests = project&.manifests
      assert_equal 1, manifests&.length
      assert_equal 2, manifests&.first&.dependencies&.length
      assert_equal 4, project&.graph&.length
    end

    test "project contains manifests with same ecosystem and path" do
      res = twirp_response_class.new(
        repository_id: 1,
        commit_oid: "1234av",
        status: :JOB_STATUS_COMPLETED,
        manifests: [
          generate_manifest(filename: "package.json", ecosystem: :ECOSYSTEM_NPM),
          generate_manifest(filename: "package-lock.json", ecosystem: :ECOSYSTEM_NPM),
          generate_manifest(path: "./folder", filename: "package-lock.json", ecosystem: :ECOSYSTEM_NPM),
        ]
      )

      obj = Reachability::ObjectHelper.create_reachability_object(res)
      assert_equal 2, obj.projects.length

      projects_hash = obj.projects.map { |p| [p.manifests.length, p.manifests.map(&:source_location)] }.to_h
      assert_equal projects_hash[2], ["./package.json", "./package-lock.json"]
      assert_equal projects_hash[1], ["./folder/package-lock.json"]
    end

    test "manifests in same path but different ecosystems are in separate projects" do
      res = twirp_response_class.new(
        repository_id: 1,
        commit_oid: "1234av",
        status: :JOB_STATUS_COMPLETED,
        manifests: [
          generate_manifest(filename: "package.json", ecosystem: :ECOSYSTEM_NPM),
          generate_manifest(filename: "pom.xml", ecosystem: :ECOSYSTEM_MAVEN),
        ]
      )

      obj = Reachability::ObjectHelper.create_reachability_object(res)
      assert_equal 2, obj.projects.length

      projects_sizes = obj.projects.map { |p| p.manifests.length }
      assert_same_elements projects_sizes, [1, 1]
    end

    test "only direct dependencies end up in manifest" do
      dependencies_count = @manifest_1.dependencies.length
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)
      project = T.must(obj.projects.first)
      manifest = T.must(project.manifests.first)

      assert_equal 2, manifest.dependencies.length
      refute_equal dependencies_count, manifest.dependencies.length
      assert_same_elements %w[dependency_1 dependency_2], manifest.dependencies.map { |d| project.graph[d.node]&.package_name }
    end

    test "transitive dependencies are in project graph" do
      dependencies_count = @manifest_1.dependencies.length
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)
      project = T.must(obj.projects.first)
      graph = project.graph

      assert_equal dependencies_count, graph.length
      packages = %w[dependency_1 dependency_2 transitive_dependency_1 transitive_dependency_2]
      assert_same_elements packages, graph.values.map(&:package_name)
    end
  end

  context "vulnerabilities" do
    test "only returns vulnerabilities applicable to package versions in graph" do
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)

      refute_empty obj.vulnerabilities
      assert_equal 2, obj.vulnerabilities.length
      assert_same_elements [@vuln1, @vuln3].map(&:ghsa_id), obj.vulnerabilities.map(&:ghsa_id)
    end

    test "return vulnerabilities for all manifests" do
      manifest_2 = generate_manifest(path: "./folder", filename: "package-lock.json", ecosystem: :ECOSYSTEM_NPM, direct_deps_count: 1)
      manifest_2.dependencies << Github::DependencyGraphPlatform::Types::V1::Dependency.new(
        id: "abcd123",
        name: "dependency_1",
        version: "3.2",
        scope: :SCOPE_RUNTIME,
        relationship: :RELATIONSHIP_DIRECT
      )

      res = twirp_response_class.new(
        repository_id: 1,
        commit_oid: "1234ab",
        status: :JOB_STATUS_COMPLETED,
        manifests: [@manifest_1, manifest_2])

      obj = Reachability::ObjectHelper.create_reachability_object(res)

      refute_empty obj.vulnerabilities
      assert_equal 3, obj.vulnerabilities.length
      assert_same_elements [@vuln1, @vuln2, @vuln3].map(&:ghsa_id), obj.vulnerabilities.map(&:ghsa_id)
    end

    test "only return vulnerabilities applicable to the correct ecosystem" do
      vuln4 = create(:vulnerability, ecosystem: "maven", with_ranges: 0)
      vvr4  = create(:vulnerable_version_range,
                     ecosystem: "maven",
                     affects: "dependency_1",
                     requirements: "< 2.4.0",
                     vulnerability: vuln4
                    )

      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)
      assert_equal 2, obj.vulnerabilities.length
      assert_same_elements [@vuln1, @vuln3].map(&:ghsa_id), obj.vulnerabilities.map(&:ghsa_id)
    end

    test "can only return vulnerabilities with vulnerable functions" do
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response, only_vulnerable_functions: true)

      refute_empty obj.vulnerabilities
      assert_equal 1, obj.vulnerabilities.length
      assert_same_elements [@vuln3.ghsa_id], obj.vulnerabilities.map(&:ghsa_id)
    end

    test "tracks duration of vulnerability fetching" do
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response)
      assert_dogstats_timing(1, "reachability.fetch_vulnerabilities.time", tags: ["only_vulnerable_functions:false"])
    end

    test "tracks number of vulnerable functions found" do
      obj = Reachability::ObjectHelper.create_reachability_object(@twirp_response, only_vulnerable_functions: true)
      assert_dogstats_count_value(1, "reachability.fetch_vulnerabilities.count", tags: ["only_vulnerable_functions:true"])
    end
  end

  def generate_manifest(path: ".", filename:, ecosystem:, direct_deps_count: 0, create_transitives: false)
    Github::DependencyGraphPlatform::Types::V1::Manifest.new(
      id: [ecosystem, path, filename].hash.to_s,
      ecosystem: ecosystem,
      path: path,
      filename: filename,
      dependencies: if direct_deps_count
                      generate_dependencies(path:, ecosystem:, direct_deps_count:, create_transitives:)
                    else
                      []
                    end
    )
  end

  def generate_dependencies(path:, ecosystem:, direct_deps_count:, create_transitives:)
    deps = []

    (1..direct_deps_count).each do |i|
      dep_name, version = "dependency_#{i}", "1.0.#{i}"
      dependency_hash = [ecosystem, path, dep_name, version].hash.to_s

      direct_dependency = Github::DependencyGraphPlatform::Types::V1::Dependency.new(
        id: dependency_hash,
        manifest_path: path,
        name: dep_name,
        version: version,
        registry_url: "registry.npmjs.org",
        scope: :SCOPE_RUNTIME,
        relationship: :RELATIONSHIP_DIRECT,
        malformed: false,
        transitive_dependencies: []
      )

      deps.push(direct_dependency)

      if create_transitives
        transitive_dep_name = "transitive_#{dep_name}"
        transitive_dependency_hash = [ecosystem, path, transitive_dep_name, version].hash.to_s
        direct_dependency.transitive_dependencies << Github::DependencyGraphPlatform::Types::V1::TransitiveDependency.new(id: transitive_dependency_hash)

        transitive_dependency = Github::DependencyGraphPlatform::Types::V1::Dependency.new(
          id: transitive_dependency_hash,
          manifest_path: path,
          name: transitive_dep_name,
          version: version,
          registry_url: "registry.npmjs.org",
          scope: :SCOPE_RUNTIME,
          relationship: :RELATIONSHIP_TRANSITIVE,
          malformed: false,
          transitive_dependencies: []
        )

        deps.push(transitive_dependency)
      end
    end

    deps
  end
end
