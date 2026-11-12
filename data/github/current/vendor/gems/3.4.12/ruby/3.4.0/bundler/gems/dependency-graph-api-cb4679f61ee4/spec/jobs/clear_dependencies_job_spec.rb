require "rails_helper"

describe ClearDependenciesJob, type: :job do

  let(:owner_id) { 98765 }
  let(:github_repository_id) { 101 }

  describe ".queue_options" do
    it "specifies a 10-minute redelivery timeout" do
      expect(described_class.queue_options).to eq(redelivery_timeout_secs: 600)
    end
  end

  before do
    allow(Instrument).to receive(:increment)

    # Create some PackageReleases
    [[1, "package1", "4.2.1"], [1, "package2", "5.2.3"], [1, "package3", "1.0.0"]].each do |manager, name, version|
      package = Package.create(name: name)
      package.releases.create(name: version, package_manager: manager, package_name: name)
    end

    # Create some repositories for the owner
    test_repo = factory.given_repository(github_owner_id: owner_id, github_repository_id: github_repository_id)
    other_repo = factory.given_repository(github_owner_id: owner_id, github_repository_id: 999)

    # Add some manifests to the repositories
    factory.given_manifest(repository: test_repo, manifest_type: Types::Manifest[:gemfile_lock])
           .add_dependency("package1", "= 4.2.1", package_manager: 1)
           .add_dependency("package2", "= 5.2.3", package_manager: 1)

    factory.given_manifest(repository: other_repo, manifest_type: Types::Manifest[:gemfile_lock])
           .add_dependency("package3", "= 1.0.0", package_manager: 1)

    # Update the package release dependent counts for the owner
    Views::PackageReleaseDependentCount.rebuild_for(owner_id)
  end

  describe "#perform_now" do

    it "validating the test setup" do
      expect(Repository.count).to eq(2)
      expect(Manifest.count).to eq(2)
      expect(ManifestEntry.count).to eq(3)
      expect(AbstractRepositoryDependency.count).to eq(3)
      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(3)
    end

    it "skips if the repository does not exist" do
      described_class.perform_now(9999)
      expect(Instrument).to have_received(:increment).with("etl.clear_dependencies_job", {
        result: "repo_not_found",
        backfill: false
      })
    end

    it "removes dependencies but not parent repo record" do
      expect(Repository.where(github_repository_id: github_repository_id)).to_not be_empty
      described_class.perform_now(github_repository_id)
      expect(Repository.where(github_repository_id: github_repository_id)).to_not be_empty
      expect(Repository.where(github_repository_id: github_repository_id).first.manifests).to be_empty
      # it only removes the dependencies for the deleted manifest
      expect(ManifestEntry.count).to eq(1)
    end

    it "decrements package release dependent counts" do
      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(3)
      described_class.perform_now(github_repository_id)
      # it only decrements the counts for the deleted manifest
      expect(Views::PackageReleaseDependentCount.where(github_owner_id: owner_id).count).to eq(1)
    end

    it "removes abstract repository dependencies" do
      expect(AbstractRepositoryDependency.count).to eq(3)
      described_class.perform_now(github_repository_id)
      # it only removes the abstract repository dependencies for the deleted manifest
      expect(AbstractRepositoryDependency.count).to eq(1)
    end

    it "enqueues clear dependencies job into expected queue" do
      ClearDependenciesJob.perform_later(github_repository_id)
      expect(ClearDependenciesJob).to have_been_enqueued.on_queue("dependency-graph_test_dg_disabling")
    end

    it "uses correct instrumentation for success" do
      described_class.perform_now(github_repository_id)
      expect(Instrument).to have_received(:increment).with("etl.clear_dependencies_job", {
        result: "successful",
        backfill: false
      })
    end

    it "adds backfill tag to backfill jobs" do
      ClearDependenciesBackfillJob.perform_now(github_repository_id)
      expect(Instrument).to have_received(:increment).with("etl.clear_dependencies_job", {
        result: "successful",
        backfill: true
      })
    end

    it "reports to Failbot if errors" do
      allow_any_instance_of(Repository).to receive(:manifests).and_raise(StandardError.new)
      expect(Failbot).to receive(:report).once.with(anything,
        "gh.aqueduct.queue.name" => "dependency-graph_test_dg_disabling",
        "gh.aqueduct.job.name" => "ClearDependenciesJob"
      )
      expect { described_class.perform_now(github_repository_id) }.to raise_error StandardError
      expect(Instrument).to have_received(:increment).with("etl.clear_dependencies_job", {
        result: "failed",
        backfill: false,
        error: "StandardError"
      })
    end
  end
end
