require "rails_helper"
require_relative "../../lib/transitions/clear_manifest_data"

describe Transitions::ClearManifestData do
  let(:repo_one_gh_id) { 111 }
  let(:repo_two_gh_id) { 222 }
  let(:repo_three_gh_id) { 333 }

  before do
    # first repo, manifest, and dependencies
    repo_one = Repository.create!(
       github_repository_id: 111,
       nwo: "github/repo_one")

    manifest_one = Manifest.create!(
      repository_id: repo_one.id,
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

    # second repo, manifest, and dependencies
    repo_two = Repository.create!(
       github_repository_id: 222,
       nwo: "github/repo_two")

    manifest_two = Manifest.create!(
      repository_id: repo_two.id,
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

    # third repo, manifest, and dependnecies: NOT a go.sum, should be unchanged
    repo_three = Repository.create!(
       github_repository_id: 333,
       nwo: "github/repo_three")

    manifest_three = Manifest.create!(
      repository_id: repo_three.id,
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

  it "correctly cleans up go.sum manifest files and associated data, without deleting parent records (like repository)" do
    repo_one = Repository.where(github_repository_id: repo_one_gh_id).first
    expect(repo_one).to_not be_nil

    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    expect(repo_two).to_not be_nil

    repo_three = Repository.where(github_repository_id: repo_three_gh_id).first
    expect(repo_three).to_not be_nil

    manifest_one = Manifest.where(repository_id: repo_one.id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(repository_id: repo_two.id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(repository_id: repo_three.id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)

    transitionator = described_class.new({ dry_run: false, filters: { filename: "go.sum" } })
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(2)
    expect(transitionator.dependencies_deleted).to eq(8)

    # after transition run: repo models should still exist
    expect(Repository.where(github_repository_id: repo_one_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_two_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_three_gh_id).count).to eq(1)

    # after transition run: only "go.sum" manifests and dependencies should be deleted
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_one.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_two.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)
    expect(Manifest.where(repository_id: repo_three.id).count).to eq(1)
  end

  it "correctly cleans up go.sum manifest files and associated data when filtering on Package Manager" do
    repo_one = Repository.where(github_repository_id: repo_one_gh_id).first
    expect(repo_one).to_not be_nil

    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    expect(repo_two).to_not be_nil

    repo_three = Repository.where(github_repository_id: repo_three_gh_id).first
    expect(repo_three).to_not be_nil

    manifest_one = Manifest.where(repository_id: repo_one.id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(repository_id: repo_two.id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(repository_id: repo_three.id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)

    transitionator = described_class.new({ dry_run: false, filters: { package_manager: ::Types::PackageManager.coerce("go") } })
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(2)
    expect(transitionator.dependencies_deleted).to eq(8)

    # after transition run: repo models should still exist
    expect(Repository.where(github_repository_id: repo_one_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_two_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_three_gh_id).count).to eq(1)

    # after transition run: only "go.sum" manifests and dependencies should be deleted
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_one.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_two.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)
    expect(Manifest.where(repository_id: repo_three.id).count).to eq(1)
  end

  it "correctly cleans up manifest files and associated data when multiple filename filters are applied" do
    repo_one = Repository.where(github_repository_id: repo_one_gh_id).first
    expect(repo_one).to_not be_nil

    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    expect(repo_two).to_not be_nil

    repo_three = Repository.where(github_repository_id: repo_three_gh_id).first
    expect(repo_three).to_not be_nil

    manifest_one = Manifest.where(repository_id: repo_one.id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(repository_id: repo_two.id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(repository_id: repo_three.id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)

    transitionator = described_class.new({ dry_run: false, filters: { filename: ["go.sum", "Gemfile"] } })
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(3)
    expect(transitionator.dependencies_deleted).to eq(11)

    # after transition run: repo models should still exist
    expect(Repository.where(github_repository_id: repo_one_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_two_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_three_gh_id).count).to eq(1)

    # after transition run: only "go.sum" manifests and dependencies should be deleted
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_one.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_two.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_three.id).count).to eq(0)
  end

  it "correctly cleans up go.sum manifest files and associated data when multiple filter types are appliedr" do
    repo_one = Repository.where(github_repository_id: repo_one_gh_id).first
    expect(repo_one).to_not be_nil

    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    expect(repo_two).to_not be_nil

    repo_three = Repository.where(github_repository_id: repo_three_gh_id).first
    expect(repo_three).to_not be_nil

    manifest_one = Manifest.where(repository_id: repo_one.id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(repository_id: repo_two.id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(repository_id: repo_three.id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)

    filters = {
      filename: "go.sum",
      package_manager: ::Types::PackageManager.coerce("go"),
    }
    transitionator = described_class.new({ dry_run: false, filters: filters })
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(2)
    expect(transitionator.dependencies_deleted).to eq(8)

    # after transition run: repo models should still exist
    expect(Repository.where(github_repository_id: repo_one_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_two_gh_id).count).to eq(1)
    expect(Repository.where(github_repository_id: repo_three_gh_id).count).to eq(1)

    # after transition run: only "go.sum" manifests and dependencies should be deleted
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_one.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(0)
    expect(Manifest.where(repository_id: repo_two.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)
    expect(Manifest.where(repository_id: repo_three.id).count).to eq(1)
  end


  it "retries failed cleanup attempts when errors occur" do
    transitionator = described_class.new({ dry_run: false, filters: { filename: "go.sum" } })
    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    manifest_two = Manifest.where(repository_id: repo_two.id).first

    allow(transitionator).to receive(:attempt_cleanup_once).and_call_original
    expect(transitionator).to receive(:attempt_cleanup_once).with(manifest_two.id, any_args).
      at_least(Transitions::ClearManifestData::MAX_ATTEMPTS).times.
      and_raise(ActiveRecord::RecordInvalid)

    assert_raises ActiveRecord::RecordInvalid do
      transitionator.execute
    end
  end

  it "does NOT delete actual records in --dry-run mode" do
    transitionator = described_class.new({ dry_run: true, filters: { filename: "go.sum" } })
    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    repo_one = Repository.where(github_repository_id: repo_one_gh_id).first
    expect(repo_one).to_not be_nil

    repo_two = Repository.where(github_repository_id: repo_two_gh_id).first
    expect(repo_two).to_not be_nil

    repo_three = Repository.where(github_repository_id: repo_three_gh_id).first
    expect(repo_three).to_not be_nil

    manifest_one = Manifest.where(repository_id: repo_one.id)&.first
    expect(manifest_one).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_one.id).count).to eq(4)

    manifest_two = Manifest.where(repository_id: repo_two.id)&.first
    expect(manifest_two).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_two.id).count).to eq(4)

    manifest_three = Manifest.where(repository_id: repo_three.id)&.first
    expect(manifest_three).to_not be_nil
    expect(ManifestDependency.where(manifest_id: manifest_three.id).count).to eq(3)
  end

  it "handles a mini load test and batches correctly" do
    # scripting up a ton of manifests and deps-per-manifest here
    repo = Repository.create!(
       github_repository_id: 12345,
       nwo: "github/big_ol_repo")

    manifest_a = Manifest.create!(
      repository_id: repo.id,
      filename: "go.sum",
      manifest_type: :go_mod, # cheat - :go_sum was removed
      package_manager: :go,
      latest_git_ref: "abc123",
      last_pushed_at: Time.now,
      path: "projects/a")

    manifest_b = Manifest.create!(
      repository_id: repo.id,
      filename: "go.sum",
      manifest_type: :go_mod, # cheat - :go_sum was removed
      package_manager: :go,
      latest_git_ref: "abc123",
      last_pushed_at: Time.now,
      path: "projects/b")

    mds = []
    (1..(Transitions::ClearManifestData::DEPENDENCY_BATCH_SIZE * 3)).each do |ndx|
      mds << ManifestDependency.new(
        manifest_id: manifest_a.id,
        package_name: "foobar_a_#{ndx}",
        last_seen_at_revision: 1,
        requirements: "= 1.0.#{ndx}")

      mds << ManifestDependency.new(
        manifest_id: manifest_b.id,
        package_name: "foobar_b_#{ndx}",
        last_seen_at_revision: 1,
        requirements: "= 2.0.#{ndx}")
    end

    ManifestDependency.import!(mds, validate: false)

    transitionator = described_class.new({ dry_run: false, filters: { filename: "go.sum" } })
    expect(transitionator.manifests_deleted).to eq(0)
    expect(transitionator.dependencies_deleted).to eq(0)

    # note: this consumes all eligible "before fixtures" + the batches created in this test
    transitionator.execute
    expect(transitionator.manifests_deleted).to eq(4)
    expect(transitionator.dependencies_deleted).to eq(8 + (Transitions::ClearManifestData::DEPENDENCY_BATCH_SIZE * 6))

    exp_repo = Repository.where(github_repository_id: repo.id).first
    expect(exp_repo).to be_nil

    expect(Manifest.where(repository_id: repo.id).count).to eq(0)

    expect(ManifestDependency.where(manifest_id: manifest_a.id).count).to eq(0)
    expect(ManifestDependency.where(manifest_id: manifest_b.id).count).to eq(0)
  end
end
