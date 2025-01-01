# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/storage_cluster_test_helpers"

class StorageBlobTest < GitHub::TestCase
  include StorageClusterTestHelpers

  fixtures do
    @blob = Storage::Blob.create_for_uploadable(
      oid: Sham.sha256,
      size: 123,
    )

    @user = create(:user)
    @avatar = create :avatar, owner: @user, storage_blob: @blob
  end

  test "links blobs to existing fileservers" do
    fs1 = create_fs "fs-1", 1000, partitions: GitHub::Storage::Creator::PARTITIONS
    fs2 = create_fs "fs-2", 1000, partitions: GitHub::Storage::Creator::PARTITIONS
    cache1 = create_fs "fs-cache1", 1000, non_voting: true, partitions: GitHub::Storage::Creator::PARTITIONS, cache_location: "location1"

    assert_equal [], @blob.fileservers
    assert_equal 0, @blob.storage_replicas.size

    Storage::Replica.create_for_uploadable(@avatar,
      hosts: %w(fs-1 fs-2 fs-cache1),
    )

    @blob.storage_replicas.reload
    assert_equal 3, @blob.storage_replicas.size
    assert_equal %w(http://fs-1/cluster http://fs-2/cluster), @blob.fileservers.sort

    assert fs1 = Storage::FileServer.find_by_host("fs-1")
    assert fs2 = Storage::FileServer.find_by_host("fs-1")
    assert cache1 = Storage::FileServer.find_by_host("fs-cache1")
    assert_equal 16, fs1.partitions.count
    assert_equal 16, fs2.partitions.count
    assert_equal 16, cache1.partitions.count
    assert_equal [1000], fs1.partitions.map(&:disk_free).uniq
    assert_equal [1000], fs2.partitions.map(&:disk_free).uniq
    assert_equal [1000], cache1.partitions.map(&:disk_free).uniq
  end
end
