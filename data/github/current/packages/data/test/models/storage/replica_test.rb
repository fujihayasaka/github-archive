# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/storage_cluster_test_helpers"

class StorageReplicaTest < GitHub::TestCase
  include StorageClusterTestHelpers

  fixtures do
    GitHub.storage_cluster_enabled = true
    @blob = Storage::Blob.create_for_uploadable(
      oid: Sham.sha256,
      size: 123,
    )

    @user = create(:user)
    @avatar = create :avatar, owner: @user, storage_blob: @blob
  end

  setup do
    GitHub.storage_cluster_enabled = true
  end

  teardown do
    GitHub.storage_auto_localhost_replica = nil
  end

  test "create_for_uploadable initializes references" do
    assert_equal 0, Storage::Reference.count

    Storage::Replica.create_for_uploadable(@avatar,
      hosts: %w(fs-1 fs-2),
    )

    refs = Storage::Reference.all
    assert_equal [@blob.id], refs.map(&:storage_blob_id)
    assert_equal [@avatar], refs.map(&:uploadable)
    assert_equal ["uploaded"], refs.map(&:state)
  end

  test "create_for_uploadable initializes replicas" do
    assert_equal 0, Storage::Replica.count

    Storage::Replica.create_for_uploadable(@avatar,
      hosts: %w(fs-1 fs-2),
    )

    replicas = Storage::Replica.all
    assert_equal %w(fs-1 fs-2), replicas.map(&:host).sort
    assert_equal [@blob.id, @blob.id], replicas.map(&:storage_blob_id)
  end

  test "updates reference state" do
    assert_equal [], Storage::FileServer.all.map(&:host).sort
    assert_equal 0, Storage::Replica.count
    assert_equal 0, Storage::Reference.count

    Storage::Replica.create_for_uploadable(@avatar,
      hosts: %w(fs-1 fs-2),
    )

    # the uploadable was deleted
    Storage::Reference.update_all(
      state: :deleted,
    )

    assert_equal ["deleted"], Storage::Reference.all.map(&:state)

    # the uploadable was re-uploaded
    Storage::Replica.create_for_uploadable(@avatar,
      hosts: %w(fs-1 fs-2),
    )

    assert_equal ["uploaded"], Storage::Reference.all.map(&:state)
  end

  test "builds fileserver urls for replication" do
    GitHub.storage_replica_count = 2
    GitHub.storage_non_voting_replica_count = 1
    fe1 = create_fs "alambic-fe1"
    fe2 = create_fs "alambic-fe2"
    nv1 = create_fs "alambic-nv1", non_voting: true, datacenter: "dc1"
    cache1 = create_fs "alambic-cache1", 100.terabytes, non_voting: true, datacenter: "dc1", cache_location: "location1"

    assert_same_elements [
      "http://alambic-fe1/cluster",
      "http://alambic-fe2/cluster",
      "http://alambic-nv1/cluster",
    ], Storage::Replica.replication_fileservers
  end

  test "auto-fills localhost in dev with storage_replica_count=1" do
    GitHub.storage_replica_count = 1
    GitHub.storage_auto_localhost_replica = true

    assert_equal %w(http://localhost/cluster), Storage::Replica.replication_fileservers
    assert_equal 0, Storage::FileServer.count
  end

  test "raises with no hosts in dev with storage_replica_count > 1" do
    GitHub.storage_replica_count = 3
    GitHub.storage_auto_localhost_replica = true

    assert_equal 0, Storage::FileServer.count

    assert_raises Storage::ReplicationError do
      Storage::Replica.replication_fileservers
    end
  end

  test "raises with no hosts in prod with storage_replica_count=1" do
    GitHub.storage_replica_count = 1
    GitHub.storage_auto_localhost_replica = false

    assert_equal 0, Storage::FileServer.count

    assert_raises Storage::ReplicationError do
      Storage::Replica.replication_fileservers
    end
  end

  test "raises with no hosts in prod with storage_replica_count > 1" do
    GitHub.storage_replica_count = 3
    GitHub.storage_auto_localhost_replica = false

    assert_equal 0, Storage::FileServer.count

    assert_raises Storage::ReplicationError do
      Storage::Replica.replication_fileservers
    end
  end
end
