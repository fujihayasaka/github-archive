# frozen_string_literal: true
module DependencyGraph
  module ObjectModel
  end
end

require_relative "../../../rails_helper"
require_relative "../../../spec_helper"
require_relative "../../../../lib/dependency_graph/object_model/ds_api_manifest"

describe DependencyGraph::ObjectModel::DSAPIManifest do
  describe "the collapse_ds_api_manifests method" do
    it "collapses based on manifest name when there's no file_path" do
      # this response is inspired by the customer snapshot from https://github.com/github/dependency-graph/issues/1240
      dsapiResponse = Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse.new(
        all_manifests: [
          Github::DependencySnapshotsApi::Manifest.new(
            name: "pom.xml",
            # note: no file_path for this manifest
            dependencies: {
              "byte-buddy": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:maven/net.bytebuddy/byte-buddy@1.12.5",
                dependencies: []
              ),
              "junit-platform-commons": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:maven/org.junit.platform/junit-platform-commons@1.8.2",
                dependencies: [],
              ),
            }
          ),
          Github::DependencySnapshotsApi::Manifest.new(
            name: "modules/generator-core/pom.xml",
            # note: no file_path for this manifest
            dependencies: {
              "jackson-databind": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.12.1",
                dependencies: [],
              )
            }
          ),
          Github::DependencySnapshotsApi::Manifest.new(
            name: "modules/generator-maven-plugin/pom.xml",
            # note: no file_path for this manifest
            dependencies: {
              "maven-repository-metadata": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:maven/org.apache.maven/maven-repository-metadata@3.3.9",
                dependencies: [],
              )
            }
          ),
          Github::DependencySnapshotsApi::Manifest.new(
            # we want this to be combined with the pom.xml above
            name: "more pom.xml stuff",
            file_path: "pom.xml",
            dependencies: {
              "mockk-agent-api": Github::DependencySnapshotsApi::Manifest::Dependency.new(
                package_url: "pkg:maven/io.mockk/mockk-agent-api@1.12.2",
                dependencies: [],
              )
            }
          )
        ],
        manifests: {
          # unused
        }
      )

      result = described_class.collapse_ds_api_manifests(dsapiResponse.all_manifests)
      expect(result.map(&:name)).to match_array(["pom.xml", "modules/generator-core/pom.xml", "modules/generator-maven-plugin/pom.xml"])

      manifests = result.group_by(&:name).transform_values(&:first)
      expect(manifests["pom.xml"].dependencies.map(&:package_url).map(&:name)).to match_array(["byte-buddy", "junit-platform-commons", "mockk-agent-api"])
      expect(manifests["modules/generator-core/pom.xml"].dependencies.map(&:package_url).map(&:name)).to match_array(["jackson-databind"])
      expect(manifests["modules/generator-maven-plugin/pom.xml"].dependencies.map(&:package_url).map(&:name)).to match_array(["maven-repository-metadata"])
    end
  end
end
