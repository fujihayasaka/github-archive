# frozen_string_literal: true

require "rails_helper"
require "dependency_graph/manifest_dependency_replicator"

describe DependencyGraph::ManifestDependencyReplicator do
  let(:replicator) { described_class.new }
  let(:manifest) { factory.given_manifest.manifest }

  let(:base_dependency) {
    {
      manifest_id: manifest.id,
      package_manager: Types::PackageManager::RUBYGEMS,
      package_name: "rails",
      requirements: "< 5.0",
      encoded_lower_bound: 0,
      encoded_upper_bound: 555,
      scope: Types::Scope::DEVELOPMENT,
      last_seen_at_revision: 1,
    }
  }
  let(:manifest_dependency) { ManifestDependency.new(**base_dependency) }
  let(:manifest_dependency_update) {
    ManifestDependency.new(**base_dependency.merge(
      last_seen_at_revision: 2,
      scope: Types::Scope::RUNTIME,
    ))
  }
  let(:manifest_dependency_version_update) {
    ManifestDependency.new(**base_dependency.merge(
      requirements: "= 6.0",
      last_seen_at_revision: 3,
    ))
  }

  before do
    allow(Instrument).to receive(:count)
  end

  it "does nothing when given an empty list" do
    expect(ManifestEntry).not_to receive(:import)

    expect {
      replicator.to_manifest_entries([])
    }.not_to change(ManifestEntry, :count)
  end

  it "imports a single package, package version, and manifest entry from a manifest dependency" do
    expect {
      replicator.to_manifest_entries([manifest_dependency])
    }.to change(ManifestEntry, :count).by(1)

    package = ManifestPackage.find_by!(
      package_manager: manifest_dependency.package_manager,
      package_name: manifest_dependency.package_name
    )

    package_version = ManifestPackageVersion.find_by!(
      manifest_package_id: package.id,
      requirements: manifest_dependency.requirements
    )

    manifest_entry = ManifestEntry.find_by!(
      manifest_id: manifest_dependency.manifest_id,
      manifest_package_version_id: package_version.id,
    )

    expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency.last_seen_at_revision)
    expect(manifest_entry.scope).to eq(manifest_dependency.scope)

    expect(Instrument).to have_received(:count).with("manifest_dependency_replicator.packages_imported", 1)
    expect(Instrument).to have_received(:count).with("manifest_dependency_replicator.package_versions_imported", 1)
    expect(Instrument).to have_received(:count).with("manifest_dependency_replicator.entries_created", 1)
  end

  it "importing the same ManifestDependency twice does not create duplicate ManifestEntries" do
    expect {
      replicator.to_manifest_entries([manifest_dependency])
      replicator.to_manifest_entries([manifest_dependency])
    }.to change(ManifestEntry, :count).by(1)

    expect(manifest.entries.count).to eq(1)

    manifest_entry = manifest.entries.first

    expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency.last_seen_at_revision)
    expect(manifest_entry.scope).to eq(manifest_dependency.scope)
  end

  it "importing an updated ManifestDependency without a version update updates the existing ManifestEntry" do
    expect {
      replicator.to_manifest_entries([manifest_dependency])
    }.to change(ManifestEntry, :count).by(1)

    expect(ManifestPackage.count).to eq(1)
    expect(ManifestPackageVersion.count).to eq(1)
    expect(manifest.entries.count).to eq(1)
    manifest_entry = manifest.entries.first

    expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency.last_seen_at_revision)
    expect(manifest_entry.scope).to eq(manifest_dependency.scope)

    expect {
      replicator.to_manifest_entries([manifest_dependency_update])
    }.not_to change(ManifestEntry, :count)

    expect(ManifestPackage.count).to eq(1)
    expect(ManifestPackageVersion.count).to eq(1)
    expect(manifest.entries.count).to eq(1)
    manifest_entry = manifest.entries.first

    expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency_update.last_seen_at_revision)
    expect(manifest_entry.scope).to eq(manifest_dependency_update.scope)

    expect(Instrument).to have_received(:count).twice.with("manifest_dependency_replicator.entries_created", 1)
  end

  it "importing an updated ManifestDependency with a version update creates a new ManifestPackageVersion" do
    expect {
      replicator.to_manifest_entries([manifest_dependency])
    }.to change(ManifestEntry, :count).by(1)

    expect(ManifestPackage.count).to eq(1)
    expect(ManifestPackageVersion.count).to eq(1)
    expect(manifest.entries.count).to eq(1)

    expect {
      replicator.to_manifest_entries([manifest_dependency_version_update])
    }.to change(ManifestEntry, :count).by(1)

    expect(ManifestPackage.count).to eq(1)
    expect(ManifestPackageVersion.count).to eq(2)
    expect(manifest.entries.count).to eq(2)
    manifest_entry = manifest.entries.last

    expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency_version_update.last_seen_at_revision)
    expect(manifest_entry.scope).to eq(manifest_dependency_version_update.scope)
  end

  context "when case differs" do
    let(:manifest_two) { factory.given_manifest.manifest }
    let(:base_dependency) {
      {
        manifest_id: manifest.id,
        package_manager: Types::PackageManager::RUBYGEMS,
        package_name: "rails",
        requirements: "< 5.0.alpha",
        encoded_lower_bound: 0,
        encoded_upper_bound: 555,
        scope: Types::Scope::DEVELOPMENT,
        last_seen_at_revision: 1,
      }
    }

    let(:manifest_dependency_different_case_requirements) {
      ManifestDependency.new(**base_dependency.merge(
                               manifest_id: manifest_two.id,
                               requirements: "< 5.0.Alpha",
                             ))
    }

    let(:manifest_dependency) { ManifestDependency.new(**base_dependency) }
    let(:manifest_dependency_update) {
      ManifestDependency.new(**base_dependency.merge(
                               last_seen_at_revision: 2,
                               scope: Types::Scope::RUNTIME,
                             ))
    }
    let(:manifest_dependency_version_update) {
      ManifestDependency.new(**base_dependency.merge(
                               requirements: "= 6.0",
                               last_seen_at_revision: 3,
                             ))
    }

    let(:manifest_dependency_package_case_update) {
      ManifestDependency.new(**base_dependency.merge(
                               package_name: "Rails",
                               requirements: "= 6.0",
                               last_seen_at_revision: 3,
                             ))
    }

    it "importing a ManifestDependency with requirements that have already been saved under a different case works" do
      expect {
        replicator.to_manifest_entries([manifest_dependency])
      }.to change(ManifestEntry, :count).by(1)

      expect(ManifestPackage.count).to eq(1)
      expect(ManifestPackageVersion.count).to eq(1)
      expect(manifest.entries.count).to eq(1)

      expect {
        replicator.to_manifest_entries([manifest_dependency_different_case_requirements])
      }.to change(ManifestEntry, :count).by(1)

      expect(ManifestPackage.count).to eq(1)
      expect(ManifestPackageVersion.count).to eq(1)
      expect(manifest_two.entries.count).to eq(1)
      manifest_entry = manifest_two.entries.last

      expect(manifest_entry.scope).to eq(manifest_dependency_version_update.scope)
    end

    it "importing an updated ManifestDependency with a differently cased package creates a new ManifestPackageVersion" do
      expect {
        replicator.to_manifest_entries([manifest_dependency])
      }.to change(ManifestEntry, :count).by(1)

      expect(ManifestPackage.count).to eq(1)
      expect(ManifestPackageVersion.count).to eq(1)
      expect(manifest.entries.count).to eq(1)

      expect {
        replicator.to_manifest_entries([manifest_dependency_package_case_update])
      }.to change(ManifestEntry, :count).by(1)

      expect(ManifestPackage.count).to eq(1)
      expect(ManifestPackageVersion.count).to eq(2)
      expect(manifest.entries.count).to eq(2)
      manifest_entry = manifest.entries.last

      expect(manifest_entry.last_seen_at_revision).to eq(manifest_dependency_package_case_update.last_seen_at_revision)
      expect(manifest_entry.scope).to eq(manifest_dependency_version_update.scope)
    end
  end

  it "importing an updated ManifestDependency with a nil package_manager, package_name, or requirements does not import anything" do
    nil_pm = ManifestDependency.new(**base_dependency.except(:package_manager))
    nil_name = ManifestDependency.new(**base_dependency.except(:package_name))
    nil_requirements = ManifestDependency.new(**base_dependency.except(:requirements))

    expect {
      replicator.to_manifest_entries([nil_pm, nil_name, nil_requirements])
    }.to change(ManifestEntry, :count).by(0)

    # Creation will fail for each of the 3 cases because we won't be able to resolve a ManifestPackage or ManifestPackageVersion
    expect(Instrument).to have_received(:count).with("manifest_dependency_replicator.entries_failed_creates", 3)
  end
end
