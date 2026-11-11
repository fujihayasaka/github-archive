# frozen_string_literal: true
require "rails_helper"
require "dependency_graph/object_model/ds_api_dependency"

describe DependencyGraph::ObjectModel::DSAPIDependency do
  let(:dsapi_dependency_name) { "byte-buddy" }

  let(:dsapi_dependency) do
    Github::DependencySnapshotsApi::Manifest::Dependency.new(
      package_url: "pkg:maven/net.bytebuddy/byte-buddy@12.5.1",
      dependencies: []
    )
  end

  let(:dsapi_dependency_no_version) do
    Github::DependencySnapshotsApi::Manifest::Dependency.new(
      package_url: "pkg:maven/net.bytebuddy/byte-buddy",
      dependencies: []
    )
  end

  describe "#to_proto" do
    it "returns a proto object for a PURL with a name and version" do
      dependency = described_class.new(dsapi_dependency_name, dsapi_dependency)

      expect(dependency.full_package_name).to eq("net.bytebuddy:byte-buddy")
      expect(dependency.package_manager).to eq(Types::PackageManager::MAVEN)
      expect(dependency.requirement_set.serialize).to eq("= 12.5.1")
    end

    it "returns a proto object with a wildcard requirement for a PURL with no version" do
      dependency = described_class.new(dsapi_dependency_name, dsapi_dependency_no_version)

      expect(dependency.full_package_name).to eq("net.bytebuddy:byte-buddy")
      expect(dependency.package_manager).to eq(Types::PackageManager::MAVEN)

      # A PURL with no version should result in a Requirement Set with one range,
      # containing a single wildcard requirement

      expect(dependency.requirement_set.ranges.count).to eq(1)
      range = dependency.requirement_set.ranges.first

      expect(range.requirements.count).to eq(1)
      requirement = range.requirements.first

      expect(requirement.wildcard?).to eq(true)
    end
  end
end
