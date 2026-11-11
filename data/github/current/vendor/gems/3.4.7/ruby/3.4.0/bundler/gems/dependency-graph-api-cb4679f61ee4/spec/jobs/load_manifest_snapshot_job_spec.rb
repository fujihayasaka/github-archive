require "rails_helper"
require_relative "../../lib/dependency_snapshots_api/snapshots_client.rb"

describe LoadManifestSnapshotJob do
  include ActiveJob::TestHelper

  def manifest_content
    content = <<-PKGLOCK
{
  "name": "simple",
  "version": "0.1.2",
  "lockfileVersion": 1,
  "requires": true,
  "dependencies": {}
}
      PKGLOCK

    content
  end

  def associated_manifest_content
    content = <<-PKGJSON
{
  "name": "simple",
  "version": "0.1.2",
  "license": "MIT",
  "dependencies": {},
  "devDependencies": {}
}
      PKGJSON

    content
  end

  def blob_operations_provider
    SnapshotRequests::Provider::NoOpProvider.new(
      get_blob_returns: {
        "b52f254598ec86b5bf87327e598661f09e52be0f" => OpenStruct.new(content: manifest_content),
        "0272f4b19df2c52ed179a58630535c92e8c940b1" => OpenStruct.new(content: associated_manifest_content),
      }
    )
  end

  def manifest_change_event
    {
      repository_id: 123,
      repository_private: false,
      repository_fork: false,
      manifest_file: {
        filename: "package-lock.json",
        path: "",
        git_ref: "c08a08d39619e804a70ef6a1739a920ae73a402a",
        pushed_at: { seconds: 1665438024, nanos: 0 },
        blob_oid: "b52f254598ec86b5bf87327e598661f09e52be0f",
      },
      repository_nwo: "foo/bar",
      repository_stargazer_count: 3,
      owner_id: 456,
      is_backfill: false,
      repository_max_manifests: 150,
      snapshot_metadata: {
        associated_manifest: {
          filename: "package.json",
          path: "",
          git_ref: "c08a08d39619e804a70ef6a1739a920ae73a402a",
          pushed_at: { seconds: 1665438024, nanos: 0 },
          blob_oid: "0272f4b19df2c52ed179a58630535c92e8c940b1",
        },
        ref: "refs/heads/main",
        commit_sha: "c08a08d39619e804a70ef6a1739a920ae73a402a",
        push_id: 789
      },
    }
  end

  it "enqueues manifest snapshot job into expected queue" do
    LoadManifestSnapshotJob.perform_later(manifest_change_event)
    expect(LoadManifestSnapshotJob).to have_been_enqueued.on_queue("dependency-graph_test_manifest_snapshots_npm")
  end

  it "parses and submits a manifest snapshot from a change event" do
    allow_any_instance_of(LoadManifestSnapshotJob).to receive(:spokes_client).and_return(blob_operations_provider)

    expect_any_instance_of(DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient).to receive(:create_dependency_snapshot).once
    allow(Rails.application.stats).to receive(:increment)

    perform_enqueued_jobs do
      LoadManifestSnapshotJob.perform_later(manifest_change_event)
    end

    expect(Rails.application.stats).to have_received(:increment).with("etl.manifest_snapshot.loaded",
      hash_including(tags: array_including(
          "package_manager:npm",
          "manifest_type:package_lock_json",
    )))

    expect(Rails.application.stats).to have_received(:increment).with("etl.manifest_snapshot.submit.success",
      hash_including(tags: array_including(
          "package_manager:npm",
          "manifest_type:package_lock_json",
    )))
  end
end
