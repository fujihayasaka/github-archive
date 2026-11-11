require "rails_helper"
require_relative "../../lib/transitions/destroy_orphaned_manifests"

TEST_DATA_DIR = "spec/transitions/orphaned-manifests-data"

describe Transitions::DestroyOrphanedManifests do
  let(:repo) { Repository.create!(github_repository_id: 1, nwo: "github/repo_one") }
  let(:non_existent_repo_id) { 999 }
  let(:manifest_one_id) { 111 }
  let(:manifest_two_id) { 222 }
  let(:manifest_three_id) { 333 }

  before(:each) do
    # first manifest, and dependencies (not orphaned)
    manifest_one = Manifest.create!(
      id: manifest_one_id,
      repository_id: repo.id,
      filename: "go.sum",
      manifest_type: :go_mod, # cheat - :go_sum was removed
      package_manager: :go,
      latest_git_ref: "abc123",
      last_pushed_at: Time.now,
      path: "")

    ManifestDependency.create!(
      manifest_id: manifest_one.id,
      package_name: "github.com/gorilla/mux",
      last_seen_at_revision: 1,
      requirements: "= 1.0.0")

    ManifestDependency.create!(
      manifest_id: manifest_one.id,
      package_name: "github.com/pkg/errors",
      last_seen_at_revision: 1,
      requirements: "= 2.0.0")

    ManifestDependency.create!(
      manifest_id: manifest_one.id,
      package_name: "cloud.google.com/go",
      last_seen_at_revision: 1,
      requirements: "< 3.0.0")

    ManifestDependency.create!(
      manifest_id: manifest_one.id,
      package_name: "go.uber.org/atomic",
      last_seen_at_revision: 1,
      requirements: "< 4.0.0")

    # second manifest, and dependencies (orphaned)
    manifest_two = Manifest.create!(
      id: manifest_two_id,
      repository_id: non_existent_repo_id,
      filename: "go.sum",
      manifest_type: :go_mod, # cheat - :go_sum was removed
      package_manager: :go,
      latest_git_ref: "abc123",
      last_pushed_at: Time.now,
      path: "src/internal/tools")

    ManifestDependency.create!(
      manifest_id: manifest_two.id,
      package_name: "github.com/aws/aws-sdk-go",
      last_seen_at_revision: 1,
      requirements: "= 1.44.129")

    ManifestDependency.create!(
      manifest_id: manifest_two.id,
      package_name: "github.com/x/test",
      last_seen_at_revision: 1,
      requirements: "= 0.3.7")

    ManifestDependency.create!(
      manifest_id: manifest_two.id,
      package_name: "cloud.google.com/go",
      last_seen_at_revision: 1,
      requirements: "< 2.1.3")

    ManifestDependency.create!(
      manifest_id: manifest_two.id,
      package_name: "go.example.com/russ-dies-at-the-end",
      last_seen_at_revision: 1,
      requirements: ">= 1.2.3")

    # third orphan manifest, and dependnecies: NOT a go.sum, should be unchanged
    manifest_three = Manifest.create!(
      id: manifest_three_id,
      repository_id: non_existent_repo_id,
      filename: "Gemfile",
      manifest_type: :gemfile,
      package_manager: :rubygems,
      latest_git_ref: "abc123",
      last_pushed_at: Time.now,
      path: "")

    ManifestDependency.create!(
      manifest_id: manifest_three.id,
      package_name: "rake",
      last_seen_at_revision: 1,
      requirements: "> 1.0.0")

    ManifestDependency.create!(
      manifest_id: manifest_three.id,
      package_name: "rspec",
      last_seen_at_revision: 1,
      requirements: ">= 2.0.0")

    ManifestDependency.create!(
      manifest_id: manifest_three.id,
      package_name: "charlock_holmes",
      last_seen_at_revision: 1,
      requirements: "= 6.6.6")
  end

  it "attempts to read CSV file from default directory when not provided" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv")

    expect { transitionator.execute }.to raise_error(Errno::ENOENT, /script\/transitions\/orphaned-manifests-data\/test.csv/)
  end

  it "does not destroy manifests in dry run mode" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv", dry_run: true, data_directory: TEST_DATA_DIR)
    expect(transitionator.progress).to eq(0)
    expect(transitionator.destroyed).to eq(0)

    transitionator.execute
    expect(transitionator.progress).to eq(10)
    expect(transitionator.destroyed).to eq(0)
  end

  it "correctly destroys orphaned manifests and skips non-orphaned and non-existent manifests in write mode" do
    verify_setup

    transitionator = described_class.new(batch_size: 5, csv_name: "test.csv", dry_run: false, data_directory: TEST_DATA_DIR)
    expect(transitionator.progress).to eq(0)
    expect(transitionator.destroyed).to eq(0)

    transitionator.execute
    expect(transitionator.progress).to eq(10)
    expect(transitionator.destroyed).to eq(2)

    # after transition run: non-orphaned manifests and dependencies should NOT be deleted
    expect(ManifestDependency.where(manifest_id: manifest_one_id).count).to eq(4)

    # after transition run: orphaned manifests and dependencies should be deleted
    expect(ManifestDependency.where(manifest_id: manifest_two_id).count).to eq(0)
    expect(ManifestDependency.where(manifest_id: manifest_three_id).count).to eq(0)
  end

  def verify_setup
    expect(repo).to_not be_nil

    manifest_one = Manifest.where(id: manifest_one_id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(id: manifest_two_id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(id: manifest_three_id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)
  end
end
