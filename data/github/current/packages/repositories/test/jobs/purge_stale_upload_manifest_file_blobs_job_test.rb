# typed: strict
# frozen_string_literal: true

require "test_helper"

if GitHub.enterprise?
  class PurgeStaleUploadManifestFileBlobsJobTest < GitHub::TestCase
    test "purge uncommitted UploadManifestFiles which are older than a day" do
      GitHub.storage_cluster_enabled = true

      manifest = create(:upload_manifest, updated_at: 3.days.ago)
      files = []
      6.times do
        blob = create :storage_blob
        file = create(:upload_manifest_file, manifest: manifest, storage_blob: blob, size: blob.size)
        GitHub::Storage::Creator.track_uploadable_storage(file, hosts: [])
        files << file
      end

      assert_difference("Storage::Purge.count", files.size) do
        PurgeStaleUploadManifestFileBlobsJob.perform_now
      end
    end

    test "purge handles the case where a manifest's repo has been deleted" do
      GitHub.storage_cluster_enabled = true

      manifest = create(:upload_manifest, updated_at: 3.days.ago)
      files = []
      3.times do
        blob = create :storage_blob
        file = create(:upload_manifest_file, manifest: manifest, storage_blob: blob, size: blob.size)
        GitHub::Storage::Creator.track_uploadable_storage(file, hosts: [])
        files << file
      end

      manifest.repository.destroy

      assert_difference("Storage::Purge.count", 3) do
        PurgeStaleUploadManifestFileBlobsJob.perform_now
      end
    end
  end
end
