require "rails_helper"

describe DeleteManifestSnapshotJob do
  include ActiveJob::TestHelper

  def manifest_delete_event
    {
      repository_id: 123,
      repository_private: false,
      repository_fork: false,
      manifest_file: {
        filename: "package-lock.json",
        path: "",
        git_ref: "c08a08d39619e804a70ef6a1739a920ae73a402a",
        pushed_at: { seconds: 1665438024, nanos: 0 },
      },
      repository_nwo: "foo/bar",
      owner_id: 456,
      snapshot_metadata: {
        ref: "refs/heads/main",
        commit_sha: "c08a08d39619e804a70ef6a1739a920ae73a402a",
        push_id: 789
      },
    }
  end

  it "enqueues manifest snapshot job into expected queue" do
    DeleteManifestSnapshotJob.perform_later(manifest_delete_event)
    expect(DeleteManifestSnapshotJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_snapshots_npm")
  end

  it "parses and submits a manifest snapshot from a delete event" do
    expect_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient).to receive(:create_dependency_snapshot).once
    allow(Rails.application.stats).to receive(:increment)

    perform_enqueued_jobs do
      DeleteManifestSnapshotJob.perform_later(manifest_delete_event)
    end

    expect(Rails.application.stats).to have_received(:increment).with("etl.manifest_snapshot.submit.success",
      hash_including(tags: array_including(
          "package_manager:npm",
          "manifest_type:package_lock_json",
    )))
  end

end
