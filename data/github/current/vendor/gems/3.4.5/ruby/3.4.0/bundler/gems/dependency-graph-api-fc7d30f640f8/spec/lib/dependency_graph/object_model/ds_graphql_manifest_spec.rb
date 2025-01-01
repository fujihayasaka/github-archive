require "rails_helper"
require "dependency_graph/object_model/ds_graphql_manifest"
require "dependency_graph/object_model/ds_api_manifest"
require "dependency_graph/object_model/ds_api_dependency"

describe DependencyGraph::ObjectModel::DSGraphqlManifest do
  before do
    DependencyGraph.flipper.disable(:dependency_graph_snapshot_transitive_labels)
  end

  let(:repo_id) { 1 }

  let(:snapshot) do
    Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot.new(
      scanned: Google::Protobuf::Timestamp.from_time(Time.parse("2021-12-13T20:25:00Z")),
      detector: Github::DependencySnapshotsApi::GetDependenciesForRepositoryResponse::Snapshot::DetectorMetadata.new(
        name: "sample-snapshot.json"
      )
    )
  end

  describe "snapshots manifest path from GetDependenciesForRepository is returned as user defined it" do

    let(:snapshots_manifest_root_path) do
      DependencyGraph::ObjectModel::DSAPIManifest.new(
        Github::DependencySnapshotsApi::Manifest.new(
          name: "manifest1",
          file_path: "pom.xml",
          dependencies: {}
        )
      )
    end

    let(:snapshots_manifest_subdirectory) do
      DependencyGraph::ObjectModel::DSAPIManifest.new(
        Github::DependencySnapshotsApi::Manifest.new(
          name: "manifest1",
          file_path: "path/to/manifest/pom.xml",
          dependencies: {}
        )
      )
    end

    let(:snapshots_manifest_root_with_dot) do
      DependencyGraph::ObjectModel::DSAPIManifest.new(
        Github::DependencySnapshotsApi::Manifest.new(
          name: "manifest1",
          file_path: "./pom.xml",
          dependencies: {}
        )
      )
    end

    let(:snapshots_manifest_subdirectory_with_dot) do
      DependencyGraph::ObjectModel::DSAPIManifest.new(
        Github::DependencySnapshotsApi::Manifest.new(
          name: "manifest1",
          file_path: "./my/subdir/pom.xml",
          dependencies: {}
        )
      )
    end

    it "returns path as an empty string when path is implicitly the root" do
      manifest = described_class.new(snapshots_manifest_root_path, snapshot, repo_id)
      expect(manifest.path).to eq("")
      expect(manifest.filename).to eq("pom.xml")
    end

    it "returns path as a dot when root path is specified with a dot" do
      manifest = described_class.new(snapshots_manifest_root_with_dot, snapshot, repo_id)
      expect(manifest.path).to eq(".")
      expect(manifest.filename).to eq("pom.xml")
    end

    it "returns proper path when path is specified" do
      manifest = described_class.new(snapshots_manifest_subdirectory, snapshot, repo_id)
      expect(manifest.path).to eq("path/to/manifest")
      expect(manifest.filename).to eq("pom.xml")
    end

    it "returns proper path with a dot when path is specified with a dot" do
      manifest = described_class.new(snapshots_manifest_subdirectory_with_dot, snapshot, repo_id)
      expect(manifest.path).to eq("./my/subdir")
      expect(manifest.filename).to eq("pom.xml")
    end
  end

  describe "dependencies data" do
    let(:repository_id) { 1 }
    let(:snapshots_manifest_with_dependencies) do
      Github::DependencySnapshotsApi::Manifest.new(
        name: "manifest1",
        file_path: "Gemfile.lock",
        dependencies: {
          "faraday@0.15.4": Github::DependencySnapshotsApi::Manifest::Dependency.new(
            package_url: "pkg://gem/faraday@0.15.4",
            dependencies: [],
          ),
          "faraday@0.15.3": Github::DependencySnapshotsApi::Manifest::Dependency.new(
            package_url: "pkg://gem/faraday@0.15.3",
            dependencies: [],
          ),
          "rails@7.0.1": Github::DependencySnapshotsApi::Manifest::Dependency.new(
            package_url: "pkg://gem/rails@7.0.1",
            dependencies: [],
          )
        }
      )
    end

    it "returns a manifest with a list of dependencies with license data" do
      rails_package = Package.create!({
        name: "rails",
        package_manager: :rubygems,
        repository_id_certainty: PackageToRepoMapping::Certainty::NULL
      })

      rails_package_release = PackageRelease.create!({
        package_id: rails_package.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name: "rails",
        name: "7.0.1",
        license: "bsd-2-clause"
      })

      faraday_package = Package.create!({
        name: "faraday",
        package_manager: Types::PackageManager[:rubygems],
        github_repository_id: repository_id,
        repository_id_certainty: PackageToRepoMapping::Certainty::MATCHING_MANIFEST,
      })

      faraday_package_release_old = PackageRelease.create!({
        package_id: faraday_package.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name: "faraday",
        name: "0.15.3",
        license: "MIT"
      })

      faraday_package_release_new = PackageRelease.create({
        package_id: faraday_package.id,
        package_manager: Types::PackageManager[:rubygems],
        package_name: "faraday",
        name: "0.15.4",
        license: "GPL"
      })

      snapshots = DependencyGraph::ObjectModel::DSAPIManifest.collapse_ds_api_manifests([snapshots_manifest_with_dependencies])
      manifests = snapshots.map { |m| described_class.new(m, snapshot, repository_id) }

      expect(manifests.count).to eq(1)
      expect(manifests[0].dependencies.length).to eq(3)

      # [faraday@0.15.4, faraday@0.15.3, rails@7.0.1]
      deps = manifests[0].dependencies.sort_by(&:package_name)

      expect(deps[0].package_name.downcase).to eq(faraday_package.name)
      expect(deps[0].license).to eq(faraday_package_release_new.license)

      expect(deps[1].package_name.downcase).to eq(faraday_package.name)
      expect(deps[1].license).to eq(faraday_package_release_old.license)

      expect(deps[2].package_name.downcase).to eq(rails_package.name)
      expect(deps[2].license).to eq(rails_package_release.license)
    end
  end
end
