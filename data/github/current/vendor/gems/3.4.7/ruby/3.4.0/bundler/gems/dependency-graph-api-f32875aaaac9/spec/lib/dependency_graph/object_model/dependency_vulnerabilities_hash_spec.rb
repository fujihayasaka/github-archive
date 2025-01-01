# frozen_string_literal: true
module DependencyGraph
  module ObjectModel
  end
end

require_relative "../../../rails_helper"
require_relative "../../../spec_helper"
require_relative "../../../../lib/dependency_graph/object_model/dependency_vulnerabilities_hash"

describe DependencyGraph::ObjectModel::DependencyVulnerabilitiesHash do
  describe "hashes vulnerabilities correctly" do
    before do
      factory do
        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "System.Net.Http",
          ecosystem: "nuget",
          requirements: "> 2.0, < 4.0",
          fixed_in: "4.0.0"
        })

        VulnerableVersionRange::GitHubVulnerability.create!({
          severity: "critical",
          status: "published"
        }).vulnerable_version_ranges.create!({
          affects: "bootstrap",
          ecosystem: "npm",
          requirements: "> 2.0, < 4.0",
          fixed_in: "4.0.0"
        })

        VulnerableVersionRange.sync
      end
    end

    it "happy path" do
      dsapiResponse = Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
        manifests: {
          "package-lock.json": Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/package-lock.json",
            dependencies: {
              "bootstrap": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/bootstrap@3.0",
                dependencies: ["tunnel"]
              ),
              "tunnel": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/npm/tunnel@0.0.6",
                dependencies: [],
              ),
            }
          )
        }
      )

      dsapiManifest = DependencyGraph::ObjectModel::DSAPIManifest.new(dsapiResponse.manifests["package-lock.json"])
      generatedHash = DependencyGraph::ObjectModel::DependencyVulnerabilitiesHash.generate_hash([dsapiManifest])
      vulnerableDependency = generatedHash.keys.find { |k| k.full_package_name == "bootstrap" }
      expect(generatedHash[vulnerableDependency]).not_to be(nil)
      expect(generatedHash[vulnerableDependency].count).to be(1)
      vulnerability = generatedHash[vulnerableDependency][0]
      expect(vulnerability.package_name).to eq("bootstrap")
      expect(vulnerability.version_range).to eq("> 2.0,< 4.0")

      nonVulnerableDependency = generatedHash.keys.find { |k| k.full_package_name == "tunnel" }
      expect(generatedHash[nonVulnerableDependency]).to be(nil)
    end

    it "generates an expected hash for capitalized package names" do
      dsapiResponse = Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
        manifests: {
          "something.packages": Github::DependencySnapshotsApi::Manifest.new(
            file_path: "/some/path/something.packages",
            dependencies: {
              "bootstrap": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/nuget/System.Net.Http@3.0",
                dependencies: ["System.Net"]
              ),
              "tunnel": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:/nuget/System.Net@0.0.6",
                dependencies: [],
              ),
            }
          )
        }
      )

      dsapiManifest = DependencyGraph::ObjectModel::DSAPIManifest.new(dsapiResponse.manifests["something.packages"])
      generatedHash = DependencyGraph::ObjectModel::DependencyVulnerabilitiesHash.generate_hash([dsapiManifest])
      vulnerableDependency = generatedHash.keys.find { |k| k.full_package_name == "System.Net.Http" }
      expect(generatedHash[vulnerableDependency]).not_to be(nil)
      expect(generatedHash[vulnerableDependency].count).to be(1)
      vulnerability = generatedHash[vulnerableDependency][0]
      expect(vulnerability.package_name).to eq("System.Net.Http")
      expect(vulnerability.version_range).to eq("> 2.0,< 4.0")

      nonVulnerableDependency = generatedHash.keys.find { |k| k.full_package_name == "System.Net" }
      expect(generatedHash[nonVulnerableDependency]).to be(nil)
    end
  end
end
