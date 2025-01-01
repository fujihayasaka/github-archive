require "rails_helper"
require_relative "../../lib/transitions/delete_orphaned_manifest_entries"

TEST_DATA_DIR = "spec/transitions/orphaned-manifest-entries-data"

describe Transitions::DeleteOrphanedManifestEntries do
  let(:manifest) { Manifest.create!(filename: "go.sum", manifest_type: :go_mod, package_manager: :go, latest_git_ref: "abc123", last_pushed_at: Time.now, path: "") }
  let(:manifest_2) { Manifest.create!(filename: "go.mod", manifest_type: :go_mod, package_manager: :go, latest_git_ref: "def456", last_pushed_at: Time.now, path: "") }
  let(:manifest_entry_one_id) { 111 }
  let(:manifest_entry_two_id) { 222 }
  let(:manifest_entry_three_id) { 333 }
  let(:manifest_entry_four_id) { 444 }

  before(:each) do
    # Create some manifest packages and versions
    package = ManifestPackage.create!(package_manager: :go, package_name: "github.com/some/package")
    package_version = ManifestPackageVersion.create!(manifest_package: package, requirements: "v1.0.0")
    package_version_2 = ManifestPackageVersion.create!(manifest_package: package, requirements: "v2.0.0")

    # Create some manifest entries
    ManifestEntry.create!(id: manifest_entry_one_id, manifest_id: manifest.id, manifest_package_version: package_version, last_seen_at_revision: 1)
    ManifestEntry.create!(id: manifest_entry_two_id, manifest_id: manifest.id, manifest_package_version: package_version_2, last_seen_at_revision: 1)
    ManifestEntry.create!(id: manifest_entry_three_id, manifest_id: manifest_2.id, manifest_package_version: package_version, last_seen_at_revision: 1)
    ManifestEntry.create!(id: manifest_entry_four_id, manifest_id: manifest_2.id, manifest_package_version: package_version_2, last_seen_at_revision: 1)

    # making some orphaned
    Manifest.where(id: manifest_2.id).delete_all
  end

  it "attempts to read CSV file from default directory when not provided" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv")

    expect { transitionator.execute }.to raise_error(Errno::ENOENT, /script\/transitions\/orphaned-manifest-entries-data\/test.csv/)
  end

  it "does not delete manifest entries in dry run mode" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv", dry_run: true, data_directory: TEST_DATA_DIR)
    expect(transitionator.progress).to eq(0)
    expect(transitionator.deleted).to eq(0)

    transitionator.execute
    expect(transitionator.progress).to eq(10)
    expect(transitionator.deleted).to eq(0)
  end

  it "correctly deletes orphaned manifest entries and skips non-orphaned and non-existent ones in write mode" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv", dry_run: false, data_directory: TEST_DATA_DIR)
    expect(transitionator.progress).to eq(0)
    expect(transitionator.deleted).to eq(0)

    transitionator.execute
    expect(transitionator.progress).to eq(10)
    expect(transitionator.deleted).to eq(2)

    # after transition run: non-orphaned manifests and dependencies should NOT be deleted
    expect(ManifestEntry.where(id: manifest_entry_one_id).count).to eq(1)
    expect(ManifestEntry.where(id: manifest_entry_two_id).count).to eq(1)

    # after transition run: orphaned manifests and dependencies should be deleted
    expect(ManifestEntry.where(id: manifest_entry_three_id).count).to eq(0)
    expect(ManifestEntry.where(id: manifest_entry_four_id).count).to eq(0)
  end

  def verify_setup
    expect(manifest).to_not be_nil

    manifest_entry_one = ManifestEntry.where(id: manifest_entry_one_id)&.first
    expect(manifest_entry_one).to_not be_nil

    manifest_entry_two = ManifestEntry.where(id: manifest_entry_two_id)&.first
    expect(manifest_entry_two).to_not be_nil

    manifest_entry_three = ManifestEntry.where(id: manifest_entry_three_id)&.first
    expect(manifest_entry_three).to_not be_nil

    manifest_entry_four = ManifestEntry.where(id: manifest_entry_four_id)&.first
    expect(manifest_entry_four).to_not be_nil
  end
end
