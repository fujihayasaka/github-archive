# typed: true
# frozen_string_literal: true

require "test_helper"

class MediaBlobTest < GitHub::TestCase
  fixtures do
    @asset = create(:asset)
    @owner = create :user, login: "owner"
    @user = create :user, login: "forker"
    @source = create(:public_repository, name: "repository", owner: @owner, force_user_owned: true)
    @repository = create :fork_repository, forker: @user, fork_repo: @source, force_user_owned: true

    @media_blob = create :media_blob, asset: @asset, repository_network: @repository.network, state: :verified
    @asset.reference! @media_blob
    @other_repository = create :repository, owner: @owner
  end

  teardown do
    Media::Blob.network_copy_batch_size = nil
  end

  include DogstatsTestHelpers
  include HydroTestHelpers
  include UploadableTestHelpers
  uploadable_tests_for Media::Blob

  # assert that the uploadable asset is consistent
  def assert_asset(media_blob, asset)
    assert_equal asset.oid, media_blob.oid
    assert_equal asset.size, media_blob.size
    assert asset.charset == media_blob.charset
    assert_equal asset, media_blob.asset
    assert_equal [asset], media_blob.assets
  end

  # assert that the uploadable has been created properly
  def assert_uploadable(media_blob)
    assert_equal @source.network, media_blob.repository_network
    assert media_blob.saved?
  end

  # create an uploadable
  def create_uploadable(oid, meta)
    Media::Blob.upload(@repository, oid, meta.merge(pusher: @repository.owner))
  end

  def storage_policy
    TestEnv.test_in_multitenancy_mode? ? "policy:lfs" : "policy:s3"
  end

  test "storage_provider" do
    f = Media::Blob.new

    GitHub.stubs(:s3_production_data_access_key).returns("access")
    GitHub.stubs(:s3_production_data_secret_key).returns("secret")

    f.storage_provider = nil
    assert_equal Media::Blob.storage_s3_bucket, f.storage_s3_bucket
    assert GitHub.s3_alambic_access_key == f.storage_s3_access_key
    assert GitHub.s3_alambic_secret_key == f.storage_s3_secret_key
    refute_equal "access", f.storage_s3_access_key
    refute_equal "secret", f.storage_s3_secret_key
  end

  test "resolves to 0 for networks with no lfs blobs" do
    repo = create(:repository)
    usage = Media::Blob.network_lfs_disk_usage([repo.network_id])

    assert_equal 0, usage[repo.network_id]
  end

  test "resolves correct number of networks for lfs blobs" do
    repo = create(:repository)
    other_repo = create(:repository)

    create_list(:media_blob, 3, repository_network_id: repo.network_id, state: :verified)
    create_list(:media_blob, 2, repository_network_id: other_repo.network_id, state: :verified)

    repo_usage = Media::Blob.network_lfs_disk_usage([repo.network_id])
    other_repo_usage = Media::Blob.network_lfs_disk_usage([other_repo.network_id])

    assert_equal 3, repo_usage[repo.network_id]
    assert_equal 2, other_repo_usage[other_repo.network_id]
  end

  test "#owner_asset_status with lfs" do
    Asset::Status.delete_all
    assert_nil @media_blob.owner_asset_status

    Asset::Status.build_for_owner(:lfs, @owner.id)
    refute_nil @media_blob.owner_asset_status
  end

  test "#owner_asset_status with non-lfs" do
    Asset::Status.delete_all
    assert_nil @media_blob.owner_asset_status

    Asset::Status.build_for_owner(:registry, @owner.id)
    assert_nil @media_blob.owner_asset_status
  end

  test "#owner_asset_status after public repository root is deleted" do
    # Silence audit log warnings.
    Audit.context.push(from: "stafftools/test#post")

    blob = Media::Blob.find(@media_blob.id)
    assert status = blob.owner_asset_status
    assert_equal @owner, status.owner
    assert blob.viewable?

    @source.remove(@owner, synchronous: true)

    blob = Media::Blob.find(@media_blob.id)
    assert blob.viewable?
    if TestEnv.test_with_all_emus?
      assert blob.owner_asset_status
    else
      assert_nil blob.owner_asset_status
    end
  end

  test "#responsible_owner_id after public repository root is deleted" do
    # Silence audit log warnings.
    Audit.context.push(from: "stafftools/test#post")

    assert_equal @owner.id, Media::Blob.find(@media_blob.id).responsible_owner_id

    @source.remove(@owner, synchronous: true)

    expect = TestEnv.test_with_all_emus? ? @owner.id : @user.id
    assert_equal expect, Media::Blob.find(@media_blob.id).responsible_owner_id
  end

  test "init existing blob with different size" do
    original_size = @media_blob.size
    blobs = Media::Blob.init_all(@repository, pusher: @user, objects: [{ oid: @media_blob.oid, size: @media_blob.size + 1 }])
    assert_equal original_size, @media_blob.reload.size
    assert blobs.first.errors[:size], blobs.first.errors.full_messages.to_sentence
  end

  test "inits existing and new blobs" do
    blob_changed_size = create :media_blob, repository_network: @source.network, state: :verified
    blob_archived = create :media_blob, repository_network: @source.network, state: :archived
    good_oid = Sham.sha256
    bad_size = Sham.sha256
    bad_oid = "1111111111111"
    objects = [
      { oid: @media_blob.oid, size: @media_blob.size },
      { oid: blob_changed_size.oid, size: blob_changed_size.size + 10 },
      { oid: blob_archived.oid, size: blob_archived.size },
      { oid: good_oid, size: 123 },
      { oid: bad_size, size: -123 },
      { oid: bad_oid, size: 123 },
    ]

    result = Media::Blob.init_all(@repository, pusher: @user, objects: objects)
    assert_equal objects.size, result.size
    assert_equal objects.map { |obj| obj[:oid] }, result.map(&:oid)
    assert_equal [Media::Blob], result.map { |r| r.class }.uniq

    assert_valid result[0]
    assert result[0].verified?
    refute result[1].valid?    # changed size
    assert result[1].verified? # still verified, though
    assert_valid result[2]
    assert result[2].archived? # archived
    assert_valid result[3]
    assert result[3].saved?    # good_oid
    refute result[4].valid?
    assert result[4].starter?  # bad_size
    refute result[5].valid?
    assert result[5].starter?  # bad_oid
  end

  test "inits and verifies archived blob" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    assert_equal true, @media_blob.archive
    @media_blob.reload
    assert archive = @media_blob.asset.archives.reload.first
    assert @media_blob.archived?
    assert_equal [archive, @media_blob].sort_by(&:cache_key), @media_blob.asset.references.reload.map(&:uploadable).sort_by(&:cache_key)

    blobs = Media::Blob.init_all(@repository, pusher: @user, objects: [
      { oid: @media_blob.oid, size: @media_blob.size },
    ])
    assert_equal 1, blobs.size
    assert blob = blobs.first
    assert_equal @media_blob, blob
    assert @media_blob.reload.archived?

    Timecop.freeze(DateTime.parse("2023-02-01 04:05:06 UTC")) do
      @media_blob.set_verified_state!

      if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
        assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")
      else
        assert_equal 1, hydro_message_count(schema: "billingplatform.v1.Usage")
        assert_hydro_published({
            sku: "git_lfs_storage",
            quantity: 0.000000001,
            usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
            source_uri: "gid://git-hub/Repository/#{@source.id}",
            entity: { customer_id: @owner.customer.id, organization_id: 0, repo_id: @source.id, actor_id: @owner.id }
          },
          schema: "billingplatform.v1.Usage",
          count: 1
        )
      end
    end

    assert_equal 1, blob.size
    assert_equal 1, blob.asset.size
    assert @media_blob.reload.verified?
    assert_equal [@media_blob].sort_by(&:cache_key), @media_blob.asset.references.reload.map(&:uploadable).sort_by(&:cache_key)
  end

  test "init and verify blob without asset" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: Sham.sha256, size: 123456 },
    ])
    assert_equal 1, blobs.size
    assert_valid blob = blobs.first
    assert blob.saved?

    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    Timecop.freeze(DateTime.parse("2023-02-01 04:05:06 UTC")) do
      assert_difference "Asset.count", 1 do
        assert_difference "Asset::Reference.count", 1 do
          blob.set_verified_state!
        end
      end

      if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
        assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")
      else
        assert_equal 1, hydro_message_count(schema: "billingplatform.v1.Usage")
        assert_hydro_published({
            sku: "git_lfs_storage",
            quantity: 0.000114977,
            usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
            source_uri: "gid://git-hub/Repository/#{@source.id}",
            entity: { customer_id: @owner.customer.id, organization_id: 0, repo_id: @source.id, actor_id: @owner.id }
          },
          schema: "billingplatform.v1.Usage",
          count: 1
        )
      end
    end

    blob = Media::Blob.find(blob.id)
    assert_equal 123456, blob.size
    assert_equal 123456, T.must(blob.asset).size
    assert blob.verified?
    assert_equal Asset.last, blob.asset
    assert_equal [blob.asset], blob.assets

    referenced = T.must(blob.asset).references.map(&:uploadable)
    assert referenced.include?(blob), "blob not in: #{referenced.inspect}"
  end

  test "init and verify blob with asset" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    asset = create :asset, size: 123456
    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: asset.oid, size: 123456 },
    ])
    assert_equal 1, blobs.size
    assert_valid blob = blobs.first
    assert blob.saved?

    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    Timecop.freeze(DateTime.parse("2023-02-01 04:05:06 UTC")) do
      assert_difference "Asset.count", 0 do
        assert_difference "Asset::Reference.count", 1 do
          blob.set_verified_state!
        end
      end

      if GitHub.enterprise? || TestEnv.test_in_multitenancy_mode?
        assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")
      else
        assert_equal 1, hydro_message_count(schema: "billingplatform.v1.Usage")
        assert_hydro_published({
            sku: "git_lfs_storage",
            quantity: 0.000114977,
            usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
            source_uri: "gid://git-hub/Repository/#{@source.id}",
            entity: { customer_id: @owner.customer.id, organization_id: 0, repo_id: @source.id, actor_id: @owner.id }
          },
          schema: "billingplatform.v1.Usage",
          count: 1
        )
      end
    end

    blob = Media::Blob.find(blob.id)
    assert_equal 123456, blob.size
    assert_equal 123456, T.must(blob.asset).size
    assert blob.verified?
    assert_equal asset, blob.asset
    assert_equal [blob.asset], blob.assets

    referenced = T.must(blob.asset).references.map(&:uploadable)
    assert referenced.include?(blob), "blob not in: #{referenced.inspect}"
  end

  test "init and verify blob with no size" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: Sham.sha256, size: 0 },
    ])
    assert_equal 1, blobs.size
    assert_valid blob = blobs.first
    assert blob.saved?

    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    assert_difference "Asset.count", 1 do
      assert_difference "Asset::Reference.count", 1 do
        blob.set_verified_state!
      end
    end
    assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")

    blob = Media::Blob.find(blob.id)
    assert_equal 0, blob.size
    assert_equal 0, T.must(blob.asset).size
    assert blob.verified?
    assert_equal Asset.last, blob.asset
    assert_equal [blob.asset], blob.assets

    referenced = T.must(blob.asset).references.map(&:uploadable)
    assert referenced.include?(blob), "blob not in: #{referenced.inspect}"
  end

  test "upload and verify blob" do
    blob = create_uploadable Sham.sha256, size: 123
    assert blob.saved?

    blob.set_verified_state!
    blob = Media::Blob.find(blob.id)
    assert_equal 123, blob.size
    assert_equal 123, T.must(blob.asset).size
    assert blob.verified?
    assert_equal Asset.last, blob.asset
    assert_equal [blob.asset], blob.assets

    referenced = T.must(blob.asset).references.map(&:uploadable)
    assert referenced.include?(blob), "blob not in: #{referenced.inspect}"
  end

  test "init and verify blob with new size" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: Sham.sha256, size: 123 },
    ])
    assert_equal 1, blobs.size
    assert_valid blob = blobs.first
    assert blob.saved?

    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    blob.size = 124
    assert_difference "Asset.count", 0 do
      assert_difference "Asset::Reference.count", 0 do
        assert_raises ActiveRecord::RecordInvalid do
          blob.set_verified_state!
        end
      end
    end
    assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")

    blob = Media::Blob.find(blob.id)
    assert blob.saved?

    assert_equal 123, blob.size
    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: blob.oid, size: 124 },
    ])
    assert blob = blobs.first
    assert blob.saved?

    blob.size = 124
    assert_difference "Asset.count", 1 do
      assert_difference "Asset::Reference.count", 1 do
        blob.set_verified_state!
      end
    end

    blob = Media::Blob.find(blob.id)
    assert blob.verified?
    assert_equal 124, blob.size
    assert_equal 124, T.must(blob.asset).size
    assert_equal Asset.last, blob.asset
    assert_equal [blob.asset], blob.assets

    referenced = T.must(blob.asset).references.map(&:uploadable)
    assert referenced.include?(blob), "blob not in: #{referenced.inspect}"
  end

  test "init and verify blob with new oid" do
    GitHub.flipper[:lfs_metered_billing_vnext].enable

    blobs = Media::Blob.init_all(@repository, pusher: @repository.owner, objects: [
      { oid: Sham.sha256, size: 123 },
    ])
    assert_equal 1, blobs.size
    assert_valid blob = blobs.first
    assert blob.saved?

    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references

    actual_oid = blob.oid
    blob.oid = actual_oid.reverse
    assert_difference "Asset.count", 0 do
      assert_difference "Asset::Reference.count", 0 do
        assert_raises ActiveRecord::RecordInvalid do
          blob.set_verified_state!
        end
      end
    end
    assert_equal 0, hydro_message_count(schema: "billingplatform.v1.Usage")

    blob = Media::Blob.find(blob.id)
    assert blob.saved?
    assert_equal actual_oid, blob.oid
    assert_equal 123, blob.size
    assert_nil blob.asset
    assert_equal [], blob.assets
    assert_equal [], blob.asset_references
  end

  test "gets first page of blobs" do
    blob2 = create :media_blob, repository_network: @source.network, state: :verified
    blob3 = create :media_blob, repository_network: @source.network, state: :verified
    sorted = [@media_blob, blob2, blob3].sort_by(&:oid)

    assert_equal sorted, Media::Blob.page(@source)
    assert_equal sorted, Media::Blob.page(@repository)

    assert_equal sorted[1..-1], Media::Blob.page(@source, oid: sorted[0].oid)
    assert_equal sorted[1..-1], Media::Blob.page(@repository, oid: sorted[0].oid)

    assert_equal [sorted.last], Media::Blob.page(@source, oid: sorted[1].oid)
    assert_equal [sorted.last], Media::Blob.page(@repository, oid: sorted[1].oid)
  end

  test "fetch by id" do
    assert Media::Blob.fetch_by_id(@repository, @media_blob.id)
    assert Media::Blob.fetch_by_id(@source, @media_blob.id)
    refute Media::Blob.fetch_by_id(@other_repository, @media_blob.id)
    refute Media::Blob.fetch_by_id(@repository, nil)
    refute Media::Blob.fetch_by_id(@repository, T.must(T.must(Media::Blob.last).id) + 100)
  end

  test "fetch by oids" do
    repo2 = create :repository, name: "repository2", owner: @owner
    blob_1_1 = @media_blob
    blob_1_2 = create :media_blob, asset: create(:asset), repository_network: @repository.network
    blob_2_1 = create :media_blob, asset: create(:asset), repository_network: repo2.network

    assert_same_elements [blob_1_1, blob_1_2],
      Media::Blob.fetch_all(@repository, [blob_1_1.oid, blob_1_2.oid])
    assert_same_elements [blob_1_1, blob_1_2],
      Media::Blob.fetch_all(@source, [blob_1_1.oid, blob_1_2.oid])

    assert_same_elements [blob_1_1],
      Media::Blob.fetch_all(@repository, [blob_1_1.oid, blob_2_1.oid, "abc"])
    assert_same_elements [blob_1_1],
      Media::Blob.fetch_all(@source, [blob_1_1.oid, blob_2_1.oid, "abc"])

    assert_equal [], Media::Blob.fetch_all(@repository, [])
    assert_equal [], Media::Blob.fetch_all(@repository, [blob_2_1.oid, "abc"])
  end

  test "knows if repository networks have media blobs" do
    assert Media::Blob.in_network?(@repository.network)
    assert Media::Blob.in_network?(@source.network)
    refute Media::Blob.in_network?(@other_repository.network)
  end

  test "count used storage per owner and networks without storage cluster" do
    # Blobs in a fork belonging to @owner but in a repository network owned
    # by another user should not be counted towards @owner's storage usage.
    other_repo = create :repository, owner: @user, force_user_owned: true
    other_asset = create :asset, size: 15
    other_blob = create :media_blob, asset: other_asset,
      repository_network: other_repo.network,
      created_at: 5.days.ago, state: :verified
    other_asset.reference!(other_blob)

    create(:fork_repository, forker: @owner, fork_repo: other_repo, force_user_owned: true)

    # One 1-byte blob exists in the @source.network owned by @owner
    # and should be counted towards their storage usage.
    # Duplicates of that blob which share the same Asset::Archive record
    # should also be counted towards @owner's storage usage if the duplicates
    # are in a different repository network but also owned by @owner.
    repo2 = create :repository, owner: @owner, force_user_owned: true

    dupe_blob = create :media_blob, asset: @asset, repository_network: repo2.network,
      state: :verified
    @asset.reference!(dupe_blob)

    # Blobs with older creation times should be counted.
    asset2 = create :asset, size: 10
    blob2 = create :media_blob, asset: asset2, repository_network: repo2.network,
      created_at: 5.days.ago, state: :verified
    asset2.reference!(blob2)

    # Blobs in the archived state should not be counted.
    asset3 = create :asset, size: 100
    archived_blob = create :media_blob, asset: asset3, repository_network: repo2.network,
      state: :archived
    asset3.reference!(archived_blob)
    assert archived_blob.archived?

    # Two blobs in the same network with the same creation time and size
    # should be counted even when we use a blob batch size of two or one
    # and a repository network batch size of one.
    # We create these blobs and one other with the oldest creation times,
    # so they sort first for the given repository network, with the third
    # blob sorted ahead of these two because of its smaller size.
    # This will split these two blobs into separate batches when the blob
    # batch size is two (and the repository network batch size is one).
    # In this case, the second batch should start with the second of these
    # two blobs, even though its primary ID is lower than the primary ID
    # of the first blob in the previous batch.
    asset_common_size = 2.gigabytes
    asset_common_time = 6.days.ago
    asset4 = create :asset, size: asset_common_size
    blob4 = create :media_blob, asset: asset4, repository_network: repo2.network,
      created_at: asset_common_time, state: :verified
    asset4.reference!(blob4)

    asset5 = create :asset, size: asset_common_size
    blob5 = create :media_blob, asset: asset5, repository_network: repo2.network,
      created_at: asset_common_time, state: :verified
    asset5.reference!(blob5)

    # Another blob in the same network with the same creation time as two
    # other blobs will sort ahead of them if it has a smaller size.
    # If it also has a higher ID, it should still be counted even when we
    # use a blob batch size of two or one (and a repository network batch
    # size of one).
    asset6 = create :asset, size: 4000
    blob6 = create :media_blob, asset: asset6, repository_network: repo2.network,
      created_at: asset_common_time, state: :verified
    asset6.reference!(blob6)

    # A similar set of three blobs in a third repository network belonging
    # to @owner should also be counted regardless of batch sizes.
    repo3 = create :repository, owner: @owner, force_user_owned: true

    asset_common_size = 512.kilobytes
    asset_common_time = 10.days.ago
    asset7 = create :asset, size: asset_common_size
    blob7 = create :media_blob, asset: asset7, repository_network: repo3.network,
      created_at: asset_common_time, state: :verified
    asset7.reference!(blob7)

    asset8 = create :asset, size: asset_common_size
    blob8 = create :media_blob, asset: asset8, repository_network: repo3.network,
      created_at: asset_common_time, state: :verified
    asset8.reference!(blob8)

    asset9 = create :asset, size: 300.kilobytes
    blob9 = create :media_blob, asset: asset9, repository_network: repo3.network,
      created_at: asset_common_time, state: :verified
    asset9.reference!(blob9)

    test_blob_networks = [
      { root: @source, blobs: [@media_blob] },
      { root: other_repo, blobs: [other_blob] }, # owned by @user not @owner
      { root: repo2, blobs: [dupe_blob, blob2, blob4, blob5, blob6] },
      { root: repo3, blobs: [blob7, blob8, blob9] },
    ]

    network_ids = []
    expected_total_size = 0
    expected_count = 0
    test_blob_networks.each do |n|
      next unless n[:root].owner == @owner
      network_ids << n[:root].network_id
      expected_total_size += n[:blobs].map(&:size).sum
      expected_count += n[:blobs].size
    end

    assert_equal expected_total_size, Media::Blob.storage_by_owner(@owner)

    (1..network_ids.size).each do |nb|
      assert_equal expected_total_size, Media::Blob.storage_by_owner(@owner, network_batch_size: nb)
      (1..expected_count).each do |bb|
        assert_equal expected_total_size, Media::Blob.storage_by_owner(@owner, network_batch_size: nb, blob_batch_size: bb)
      end
    end
    (1..expected_count).each do |bb|
      assert_equal expected_total_size, Media::Blob.storage_by_owner(@owner, blob_batch_size: bb)
    end

    # Test storage usage by repository network.
    (0..test_blob_networks.size).each do |i|
      test_blob_networks.combination(i) do |test_blob_networks_set|
        network_ids = []
        expected_total_size = 0
        expected_count = 0
        test_blob_networks_set.each do |n|
          network_ids << n[:root].network_id
          expected_total_size += n[:blobs].map(&:size).sum
          expected_count += n[:blobs].size
        end

        assert_equal expected_total_size, Media::Blob.storage_by_networks(network_ids)
        (1..expected_count).each do |bb|
          assert_equal expected_total_size, Media::Blob.storage_by_networks(network_ids, blob_batch_size: bb)
        end
      end
    end
  end

  test "get owner repositories with LFS" do
    # One 1-byte blob exists in the @repository.network owned by @owner
    # and so the network should be reported.

    # Another repository network which has a blob and is owned by @owner
    # should be reported also.
    repo2 = create :repository, owner: @owner, force_user_owned: true

    asset2 = create :asset, size: 10
    blob2 = create :media_blob, asset: asset2, repository_network: repo2.network,
      created_at: 5.days.ago, state: :verified
    asset2.reference!(blob2)

    # Another repository network which has no blobs and is owned by @owner
    # should not be reported.
    create :repository, name: "empty", owner: @owner, force_user_owned: true

    # A repository network owned by another user should not be reported.
    other = create :repository, name: "other", force_user_owned: true
    other_blob = create :media_blob, asset: @asset, repository_network: other.network,
      state: :verified
    @asset.reference!(other_blob)

    repos = Media::Blob.lfs_repositories(@owner)
    assert_same_elements [@source, repo2], repos
  end

  # An Asset's size should never differ from its Media::Blob's size.  This test
  # just confirms that Media::Blob isn't loading the Asset association to get the
  # size.
  test "accesses size locally" do
    orig_size = @asset.size
    assert_equal orig_size, @media_blob.size
    @media_blob.size += 1
    assert_equal orig_size, @asset.size
    assert_equal orig_size + 1, @media_blob.size
    assert_equal orig_size + 1, @media_blob.size_before_type_cast
  end

  test "validates oid presence" do
    media_blob = build :media_blob, oid: nil, repository_network: @repository.network, asset: @asset
    assert_equal false, media_blob.valid?
    refute_equal [], media_blob.errors["oid"]
  end

  test "validates asset presence" do
    media_blob = build :media_blob, storage_blob: nil, asset: nil,
      repository_network: @repository.network,
      state: :verified
    assert_equal false, media_blob.valid?
    refute_equal [], media_blob.errors["asset_id"]
  end

  test "asset size validation" do
    size = GitHub.enterprise? ? 6.gigabytes : 3.gigabytes

    media_blob = build(:media_blob,
      asset: build(:asset),
      size: size,
      repository_network: @repository.network,
    )
    assert_equal false, media_blob.valid?
    refute_equal [], media_blob.errors["size"]
  end

  test "asset size validation varies by plan" do
    owner = create :organization, admin: @user, plan: "business_plus"
    repo = create(:public_repository, owner: owner)

    media_blob = build(:media_blob,
      asset: build(:asset),
      size: 3.gigabytes,
      repository_network: repo.network,
    )
    assert_equal true, media_blob.valid?
    assert_equal [], media_blob.errors["size"]

    media_blob = build(:media_blob,
      asset: build(:asset),
      size: 6.gigabytes,
      repository_network: repo.network,
    )
    assert_equal false, media_blob.valid?
    refute_equal [], media_blob.errors["size"]
  end

  test "asset size validation succeeds without plan owner" do
    owner = create :organization, admin: @user
    repo = create(:public_repository, owner: owner)
    repo.network.root.expects(:plan_owner).returns(nil).once

    media_blob = build(:media_blob,
      asset: build(:asset),
      size: 5.gigabytes,
      repository_network: repo.network,
    )
    assert_equal true, media_blob.valid?
    assert_equal [], media_blob.errors["size"]
  end

  test "asset size validation always succeeds during copy" do
    owner = create :organization, admin: @user, plan: "business_plus"
    repo = create(:public_repository, owner: owner)

    media_blob = build(:media_blob,
      asset: build(:asset),
      size: 5.gigabytes,
      repository_network: repo.network,
    )

    assert_valid media_blob
    assert_equal [], media_blob.errors["size"]

    dup_media_blob = Media::Blob.dup_for_network([media_blob], @repository.network).first

    assert_valid dup_media_blob
    assert_equal [], dup_media_blob.errors["size"]
  end

  test "asset size validation always succeeds during archive", skip_with_all_emus: true do
    owner = create :organization, admin: @user, plan: "business_plus"
    repo = create(:public_repository, owner: owner)

    media_blob = create(:media_blob,
      asset: create(:asset, size: 5.gigabytes),
      repository_network: repo.network,
      state: :verified,
    )
    media_blob.asset.reference!(media_blob)

    assert_valid media_blob
    assert_equal [], media_blob.errors["size"]
    assert media_blob.verified?

    result = Billing::ChangeSubscription.perform owner, plan: "free", actor: owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, owner.plan_limit(:media_blob_max_size)
    end

    media_blob.reload
    assert_equal 5.gigabytes, media_blob.send(:max_blob_size)

    assert_equal true, media_blob.archive
    media_blob.reload
    assert media_blob.archived?
  end

  test "asset size validation always succeeds during unarchive", skip_with_all_emus: true do
    owner = create :organization, admin: @user, plan: "business_plus"
    repo = create(:public_repository, owner: owner)

    media_blob = create(:media_blob,
      asset: create(:asset, size: 5.gigabytes),
      repository_network: repo.network,
      state: :archived,
    )
    media_blob.asset.reference!(media_blob)

    assert_valid media_blob
    assert_equal [], media_blob.errors["size"]
    assert media_blob.archived?

    result = Billing::ChangeSubscription.perform owner, plan: "free", actor: owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, owner.plan_limit(:media_blob_max_size)
    end

    media_blob.reload
    assert_equal 5.gigabytes, media_blob.send(:max_blob_size)

    assert_equal true, media_blob.unarchive
    media_blob.reload
    assert media_blob.verified?
  end

  test "validates cannot have more than one asset" do
    asset = build(:asset)
    @media_blob.assets << asset
    assert_equal false, @media_blob.valid?
    refute_equal [], @media_blob.errors["asset_id"]
  end

  test "validates asset id matches the linked asset" do
    @media_blob.asset_id = @asset.id + 1
    assert_equal false, @media_blob.valid?
    refute_equal [], @media_blob.errors["asset_id"]
  end

  test "validates network repository presence" do
    media_blob = build :media_blob, asset: @asset, repository_network: nil
    assert_equal false, media_blob.valid?
    refute_equal [], media_blob.errors["repository_network_id"]
  end

  test "validates oid matches asset oid" do
    @media_blob.oid = "different"
    assert_equal false, @media_blob.valid?
    refute_equal [], @media_blob.errors["oid"]
  end

  test "#repository_network" do
    assert_equal @source.network, @media_blob.repository_network
  end

  test "#root_repository" do
    assert_equal @source, @media_blob.root_repository
  end

  test "#responsible_owner_id" do
    assert_equal @source.owner_id, @media_blob.responsible_owner_id
  end

  test "#repository_network_owner" do
    assert_equal @owner, @media_blob.repository_network_owner
    assert_equal @owner.id, @media_blob.repository_network_owner_id
  end

  test "#repository_network data quality" do
    @media_blob.repository_network_id = 0
    [
      lambda { @media_blob.repository_network_owner_id },
      lambda { @media_blob.repository_network_owner },
      lambda { @media_blob.root_repository },
      lambda { @media_blob.safe_repository_network },
    ].each do |attempt|
      begin
        attempt.call
        fail "attempt didn't raise"
      rescue GitHub::DataQualityError => err
        assert_equal "Data Quality error trying to access #repository_network on Media::Blob##{@media_blob.id}", err.to_s
      end
    end
  end

  test "#root_repository data quality" do
    @media_blob.repository_network.root_id = 0
    assert_equal @source.network, @media_blob.repository_network

    [
      lambda { @media_blob.repository_network_owner_id },
      lambda { @media_blob.repository_network_owner },
      lambda { @media_blob.root_repository },
    ].each do |attempt|
      begin
        attempt.call
        fail "attempt didn't raise"
      rescue GitHub::DataQualityError => err
        assert_equal "Data Quality error trying to access #root_repository on Media::Blob##{@media_blob.id}", err.to_s
      end
    end
  end

  test "#repository_network_owner data quality", skip_with_all_emus: true do
    @media_blob.root_repository.owner_id = 0
    assert_equal @source, @media_blob.root_repository

    [
      lambda { @media_blob.repository_network_owner_id },
      lambda { @media_blob.repository_network_owner },
    ].each do |attempt|
      begin
        attempt.call
        fail "attempt didn't raise"
      rescue GitHub::DataQualityError => err
        assert_equal "Data Quality error trying to access #plan_owner on Media::Blob##{@media_blob.id}", err.to_s
      end
    end
  end

  {
    "foo.png" => "image/png",
    "foo.zip" => "application/zip",
    "foo.rb" => "application/octet-stream",
    "foo.txt" => "text/plain",
    nil => "application/octet-stream",
  }.each do |path, ctype|
    test "content_type with path #{path || :nil}" do
      @media_blob.path = path
      assert_equal ctype, @media_blob.content_type
    end
  end

  test "loops through network batch" do
    asset2 = create(:asset)
    blob2 = create :media_blob, asset: asset2, repository_network: @repository.network
    asset2.reference! blob2
    asset3 = create(:asset)
    blob3 = create :media_blob, asset: asset3, repository_network: @repository.network
    asset3.reference! blob3

    # loop with default batch_size
    ids = []
    Media::Blob.each_network_batch(@repository.network) do |b|
      ids << b.map(&:id)
    end
    assert_equal [[@media_blob.id, blob2.id, blob3.id]], ids

    # loop with kwarg batch_size
    ids = []
    Media::Blob.each_network_batch(@repository.network, batch_size: 1) do |b|
      ids << b.map(&:id)
    end
    assert_equal [[@media_blob.id], [blob2.id], [blob3.id]], ids

    # loop with kwarg batch_size
    Media::Blob.network_copy_batch_size = 1
    ids = []
    Media::Blob.each_network_batch(@repository.network) do |b|
      ids << b.map(&:id)
    end
    assert_equal [[@media_blob.id], [blob2.id], [blob3.id]], ids

    # loop with first start id
    ids = []
    Media::Blob.each_network_batch(@repository.network, last_id: @media_blob.id) do |b|
      ids << b.map(&:id)
    end
    assert_equal [[blob2.id], [blob3.id]], ids

    # loop with first last start id
    ids = []
    Media::Blob.each_network_batch(@repository.network, last_id: blob3.id) do |b|
      ids << b.map(&:id)
    end
    assert_equal [], ids
  end

  test "ignores content type when verifying remote auth token" do
    policy = @media_blob.storage_policy(repository: @repository, actor: @owner)
    upload_token = @media_blob.storage_cluster_upload_token(policy)
    meta = {
      size: @media_blob.size,
      path_info: "/internal/storage/lfs/%d/objects/%s" % [
        @repository.id,
        @media_blob.oid,
      ],
      content_type: "application/octocat-stream",
    }
    result = Media::Blob.storage_verify_token(upload_token, meta)
    assert_equal @owner, result.user, "reason: #{result.reason}"
  end

  test "download_link" do
    link = @media_blob.download_link(repo: @repository)
    uri = URI.parse(link[:href])
    oid = @media_blob.oid
    if TestEnv.test_in_multitenancy_mode?
      expect_url = "/git-lfs/#{@repository.network_id}/#{oid}"
    else
      expect_url = "/alambic/media/#{@repository.network_id}/#{oid[0...2]}/#{oid[2...4]}/#{oid}"
    end
    assert_equal expect_url, uri.path, uri.inspect
    assert_equal 3600, link[:expires_in]
    time_diff = Time.parse(link[:expires_at]) - Time.now
    assert time_diff <= 3600, "#{Time.now.inspect} => #{link[:expires_at]} = #{time_diff}s"
  end

  test "stats for download_url" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @media_blob.download_url(repo: @repository)

    assert stat = stats.timings("storage_policy.url")[0]
    assert_includes stat.tags, storage_policy
    assert_includes stat.tags, "model:media/blob"
    assert_includes stat.tags, "op:download"
  end

  test "stats for download_link" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @media_blob.download_link(repo: @repository)

    assert stat = stats.timings("storage_policy.url")[0]
    assert_includes stat.tags, storage_policy
    assert_includes stat.tags, "model:media/blob"
    assert_includes stat.tags, "op:download"
  end

  test "stats for upload" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    @media_blob.lfs_upload_link(actor: @repository.owner, repo: @repository)

    assert stat = stats.timings("storage_policy.url")[0]
    assert_includes stat.tags, storage_policy
    assert_includes stat.tags, "model:media/blob"
    assert_includes stat.tags, "op:upload"
  end

  context "pointer" do
    test "parses v1 ini pointer" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:git-lfs"]
    end

    test "parses hawser ini pointer" do
      pointer = %(version https://hawser.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://hawser.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:hawser"]
    end

    test "parses media v2 ini pointer" do
      pointer = %(version http://git-media.io/v/2
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "http://git-media.io/v/2", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:git-media"]
    end

    test "parses beta pointer" do
      meta = Media::Blob.pointer("# http://git-media.io\n\nabcdef")
      refute_nil meta

      assert_equal "http://git-media.io/v/1", meta.version
      assert_equal "abcdef", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 0, meta.size
      assert_nil meta.exts

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:legacy-git-media"]
    end

    # technically _was_ a valid git lfs pointer, but no release version ever
    # used it.
    test "skips external alpha pointer" do
      assert_nil Media::Blob.pointer("# external\n\nabcdef")

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:legacy-external"]
    end

    test "parses git-media alpha pointer" do
      meta = Media::Blob.pointer("# git-media\n\nabcdef")
      refute_nil meta

      assert_equal "http://git-media.io/v/1", meta.version
      assert_equal "abcdef", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 0, meta.size
      assert_nil meta.exts

      assert_dogstats_increment 1, "lfs.parse_pointer", tags: ["version:legacy-git-media"]
    end

    test "parses v1 ini pointer with extensions" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
ext-1-bar sha256:7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
ext-9-123_ABC sha256:0c47cda934d53d7ca29d822a59531dcf6d36cbd9740a4fd0b867a0343910a715
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size

      refute_nil meta.exts
      assert_equal 10, meta.exts.length

      assert_equal "foo", meta.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", meta.exts[0].oid
      assert_equal "sha256", meta.exts[0].oid_type
      assert_equal "bar", meta.exts[1].name
      assert_equal "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730", meta.exts[1].oid
      assert_equal "sha256", meta.exts[1].oid_type
      assert_equal "123_ABC", meta.exts[9].name
      assert_equal "0c47cda934d53d7ca29d822a59531dcf6d36cbd9740a4fd0b867a0343910a715", meta.exts[9].oid
      assert_equal "sha256", meta.exts[9].oid_type

      refute meta.exts[2..8].any?
    end

    test "handles unexpected ini version" do
      pointer = %(version http://git-media.io/v/whatev
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing version" do
      pointer = %(oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty version and missing separator" do
      pointer = %(version
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty version" do
      sep = " "
      pointer = %(version#{sep}
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing OID and size" do
      pointer = %(version https://git-lfs.github.com/spec/v1)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty OID and missing separator" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty OID" do
      sep = " "
      pointer = %(version https://git-lfs.github.com/spec/v1
oid#{sep}
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty size and missing separator" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size )

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles reversed OID and size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
size 12345
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid OID type" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid foo:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:fooa214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles short OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e239
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles long OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e23930
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size foo)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles negative size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size -12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    # Note that the Git LFS client allows this condition.
    test "handles positive size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size +12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts
    end

    test "handles empty extension and missing separator" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty extension" do
      sep = " "
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo#{sep}
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid extension number" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-foo-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles large extension number" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-10-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing extension number and name and separators" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing extension number and name and separator" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext- sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty extension number and missing name" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-- sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles empty extension number" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext--foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles duplicate extension number" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
ext-0-bar sha256:7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid extension name" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-:bar sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing extension name and separator" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0 sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles missing extension name" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0- sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    # Note that the Git LFS client currently allows such extra characters.
    test "handles extra extension name" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size

      refute_nil meta.exts
      assert_equal 1, meta.exts.length

      assert_equal "foo", meta.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", meta.exts[0].oid
      assert_equal "sha256", meta.exts[0].oid_type
    end

    # Note that the Git LFS client currently allows such extra characters.
    test "handles extra characters after extension name" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo:[]() sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size

      refute_nil meta.exts
      assert_equal 1, meta.exts.length

      assert_equal "foo", meta.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", meta.exts[0].oid
      assert_equal "sha256", meta.exts[0].oid_type
    end

    test "handles invalid extension OID type" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo foo:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles invalid extension OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:foob9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles short extension OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles long extension OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c0
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extra OID and size lines" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345
oid sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
size 23456)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extra leading lines" do
      pointer = %(foo
bar
version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extra lines" do
      pointer = %(version https://git-lfs.github.com/spec/v1
foo
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
bar
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extra trailing lines" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345
foo
bar)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extra trailing whitespace lines" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345
  \t
    )

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts
    end

    test "handles extra empty lines" do
      pointer = %(
version https://git-lfs.github.com/spec/v1

ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c

ext-1-bar sha256:7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730

oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393

size 12345
)

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size

      refute_nil meta.exts
      assert_equal 2, meta.exts.length

      assert_equal "foo", meta.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", meta.exts[0].oid
      assert_equal "sha256", meta.exts[0].oid_type
      assert_equal "bar", meta.exts[1].name
      assert_equal "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730", meta.exts[1].oid
      assert_equal "sha256", meta.exts[1].oid_type
    end

    # Note that the Git LFS client allows this due to an oversight, but
    # we assume no pointers have this condition.
    test "handles extension before version" do
      pointer = %(ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles extension after size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles leading whitespace before version" do
      pointer = %(\t version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles leading whitespace before OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
\t oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles leading whitespace before size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
\t size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles leading whitespace before extension" do
      pointer = %(version https://git-lfs.github.com/spec/v1
\t ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles intermediate whitespace in version" do
      pointer = %(version \t https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles intermediate whitespace in OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid \t sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles intermediate whitespace in size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size \t 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles intermediate whitespace in extension" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo \t sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles trailing whitespace after version" do
      pointer = %(version https://git-lfs.github.com/spec/v1 \t
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles trailing whitespace after OID" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393 \t
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    # Note that the Git LFS client allows this condition.
    test "handles trailing whitespace after size" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345 \t )

      meta = Media::Blob.pointer(pointer)
      refute_nil meta

      assert_equal "https://git-lfs.github.com/spec/v1", meta.version
      assert_equal "4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393", meta.oid
      assert_equal "sha256", meta.oid_type
      assert_equal 12345, meta.size
      assert_nil meta.exts
    end

    test "handles trailing whitespace after extension" do
      pointer = %(version https://git-lfs.github.com/spec/v1
ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c \t
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer)
    end

    test "handles long string" do
      pointer = %(version https://git-lfs.github.com/spec/v1
oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
size 12345)

      assert_nil Media::Blob.pointer(pointer + (" " * 1024))
    end

    test "handles unexpected string" do
      assert_nil Media::Blob.pointer("sup")
    end

    test "handles empty string" do
      assert_nil Media::Blob.pointer("")
    end

    test "handles nil" do
      assert_nil Media::Blob.pointer(nil)
    end
  end

  context "pointer diff" do
    test "parses two v1 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
 version https://git-lfs.github.com/spec/v1
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "https://git-lfs.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses v1 and hawser pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-version https://hawser.github.com/spec/v1
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+version https://git-lfs.github.com/spec/v1
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "https://hawser.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses v1 and media v2 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-version http://git-media.io/v/2
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+version https://git-lfs.github.com/spec/v1
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/2", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses v1 and media v1 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-# git-media
-3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
+version https://git-lfs.github.com/spec/v1
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 0, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses two hawser pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
 version https://hawser.github.com/spec/v1
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "https://hawser.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://hawser.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses hawser and media v2 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-version http://git-media.io/v/2
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+version https://hawser.github.com/spec/v1
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/2", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://hawser.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses hawser and media v1 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-# git-media
-3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
+version https://hawser.github.com/spec/v1
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 0, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://hawser.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses two media v2 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
 version http://git-media.io/v/2
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/2", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "http://git-media.io/v/2", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses media v1 and v2 pointer diff" do
      diff = %(@@ -1,3 +1,3 @@
-# git-media
-3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
+version http://git-media.io/v/2
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      refute_nil pointer1
      refute_nil pointer2

      assert_equal "http://git-media.io/v/1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 0, pointer1.size
      assert_nil pointer1.exts

      assert_equal "http://git-media.io/v/2", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses two v1 pointer diff with extension added" do
      diff = %(@@ -1,3 +1,4 @@
 version https://git-lfs.github.com/spec/v1
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      assert_equal "https://git-lfs.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size
      assert_nil pointer1.exts

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size

      refute_nil pointer2.exts
      assert_equal 1, pointer2.exts.length

      assert_equal "foo", pointer2.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", pointer2.exts[0].oid
      assert_equal "sha256", pointer2.exts[0].oid_type
    end

    test "parses two v1 pointer diff with extension removed" do
      diff = %(@@ -1,4 +1,3 @@
 version https://git-lfs.github.com/spec/v1
-ext-0-bar sha256:7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)

      assert_equal "https://git-lfs.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size

      refute_nil pointer1.exts
      assert_equal 1, pointer1.exts.length

      assert_equal "bar", pointer1.exts[0].name
      assert_equal "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730", pointer1.exts[0].oid
      assert_equal "sha256", pointer1.exts[0].oid_type

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size
      assert_nil pointer2.exts
    end

    test "parses two v1 pointer diff with extension changed" do
      diff = %(@@ -1,4 +1,4 @@
 version https://git-lfs.github.com/spec/v1
-ext-0-bar sha256:7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730
-oid sha256:3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea
-size 6294357
+ext-0-foo sha256:b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c
+oid sha256:01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0
+size 6308114)

      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)
      assert_equal "https://git-lfs.github.com/spec/v1", pointer1.version
      assert_equal "3e7d379989220ede2ad46243f658f3414043dfa67cacfaedd4b46f1c037401ea", pointer1.oid
      assert_equal "sha256", pointer1.oid_type
      assert_equal 6294357, pointer1.size

      refute_nil pointer1.exts
      assert_equal 1, pointer1.exts.length

      assert_equal "bar", pointer1.exts[0].name
      assert_equal "7d865e959b2466918c9863afca942d0fb89d7c9ac0c99bafc3749504ded97730", pointer1.exts[0].oid
      assert_equal "sha256", pointer1.exts[0].oid_type

      assert_equal "https://git-lfs.github.com/spec/v1", pointer2.version
      assert_equal "01c3450384945520d3bc618f5f88f2ce02ff05d11df8b823cfa935aa0cee94c0", pointer2.oid
      assert_equal "sha256", pointer2.oid_type
      assert_equal 6308114, pointer2.size

      refute_nil pointer2.exts
      assert_equal 1, pointer2.exts.length

      assert_equal "foo", pointer2.exts[0].name
      assert_equal "b5bb9d8014a0f9b1d61e21e796d78dccdf1352f23cd32812f4850b878ae4944c", pointer2.exts[0].oid
      assert_equal "sha256", pointer2.exts[0].oid_type
    end

    test "handles long string" do
      assert Media::Blob.pointers_from_diff("*" * 2049).empty?
    end

    test "handles unexpected string" do
      assert_equal [nil, nil], Media::Blob.pointers_from_diff("sup")
    end

    test "handles nil" do
      assert Media::Blob.pointers_from_diff(nil).empty?
    end
  end

  test "#purgable" do
    assert_equal Media::Blob.purgeable, [@media_blob]

    @media_blob.archive
    assert Media::Blob.purgeable.empty?
  end

  test "#restorable" do
    @media_blob.archive
    assert_equal Media::Blob.restorable, [@media_blob]

    @media_blob.unarchive
    assert Media::Blob.restorable.empty?
  end

  test "#for_repository_network" do
    assert_equal Media::Blob.for_repository_network(@repository.network), [@media_blob]
    assert Media::Blob.for_repository_network(@other_repository.network).empty?
  end
end

class MediaBlobResponsibilityTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
    @forker = create :user, login: "forker"

    @source = create :repository, name: "source", owner: @owner
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source)

    @source_blob = create :media_blob, repository_network: @source.network
    @source_asset = @source_blob.asset

    @fork_blob = create :media_blob, repository_network: @fork.network,
      pusher: @forker,
      originating_repository: @fork
    @fork_asset = @fork_blob.asset

    @new_asset = create(:asset)
  end

  test "uploading existing source blob to public source repository" do
    Asset::Status.delete_all
    assert_nil @owner.asset_status
    blob = upload_media_blob repo: @source, asset: @source_asset, pusher: @owner
    blob.set_verified_state!

    assert_equal @source_blob, blob
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @source.id, blob.originating_repository_id
    assert_equal @owner.id, blob.pusher_id unless TestEnv.test_with_all_emus?
    assert @owner.reload.asset_status unless TestEnv.test_with_all_emus?
  end

  test "uploading existing source blob to public repository fork" do
    Asset::Status.delete_all
    assert_nil @owner.asset_status
    assert_nil @forker.asset_status
    blob = upload_media_blob repo: @fork, asset: @source_asset, pusher: @forker
    blob.set_verified_state!

    assert_equal @source_blob, blob
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @source.id, blob.originating_repository_id
    assert_equal @owner.id, blob.pusher_id unless TestEnv.test_with_all_emus?
    assert_nil @forker.reload.asset_status
    assert @owner.reload.asset_status unless TestEnv.test_with_all_emus?
  end

  test "uploading existing fork blob to public source repository" do
    blob = upload_media_blob repo: @source, asset: @fork_asset, pusher: @owner

    assert_equal @fork_blob, blob
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @fork.id, blob.originating_repository_id
    assert_equal @forker.id, blob.pusher_id
  end

  test "uploading existing fork blob to public repository fork" do
    blob = upload_media_blob repo: @fork, asset: @fork_asset, pusher: @forker

    assert_equal @fork_blob, blob
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @source, blob.root_repository
    assert_equal @fork.id, blob.originating_repository_id
    assert_equal @forker.id, blob.pusher_id
  end

  test "uploading new blob to public source repository" do
    blob = upload_media_blob repo: @source, asset: @new_asset, pusher: @owner

    assert_equal @new_asset, blob.asset
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @source.id, blob.originating_repository_id
    assert_equal @owner.id, blob.pusher_id
  end

  test "uploading new blob to public repository fork" do
    blob = upload_media_blob repo: @fork, asset: @new_asset, pusher: @forker

    assert_equal @new_asset, blob.asset
    assert_equal @source.network.id, blob.repository_network_id
    assert_equal @fork.id, blob.originating_repository_id
    assert_equal @forker.id, blob.pusher_id
  end

  test "uploading new blob to private repository fork" do
    private_source = create :private_repository, name: "private_source", owner: @owner
    private_source.add_member(@forker, adder = @owner, event = false)
    private_fork = create(:fork_repository, forker: @forker, fork_repo: private_source)

    blob = upload_media_blob repo: private_fork, asset: @new_asset, pusher: @forker

    assert_equal @new_asset, blob.asset
    assert_equal private_source.network.id, blob.repository_network_id
    assert_equal private_fork.id, blob.originating_repository_id
    assert_equal @forker.id, blob.pusher_id
  end

  def upload_media_blob(repo:, asset:, pusher: nil)
    Media::Blob.upload(repo, asset.oid,
      size: asset.size,
      pusher: pusher)
  end
end

class MediaBlobConsistencyTest < GitHub::TestCase
  skip_with_all_emus

  fixtures do
    @owner = create :user, login: "owner", plan: "business_plus"
    @org = create :organization, admin: @owner, plan: "business_plus"

    # - source
    # - org_fork (forked, then extracted from source)

    @source = create :repository, name: "source", owner: @owner
    @org_fork = create(:fork_repository, forker: @owner, organization: @org, fork_repo: @source)

    assert_equal @source.network, @org_fork.network
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @org_fork.extract! }
    refute_equal @source.reload.network, @org_fork.reload.network

    # Creating Media::Blob objects with a "verified" state causes
    # Storage::Uploadable#storage_ensure_inner_asset() to run on validation,
    # which resets the blob size to the asset size, which is 1B by default,
    # so we create assets with our intended sizes and use those explicitly.
    file1 = create :asset, size: 5.gigabytes

    @source_blob_1 = create :media_blob, repository_network: @source.network, state: :verified,
      asset: file1
    @org_blob_2 = create :media_blob, repository_network: @org_fork.network, state: :verified,
      asset: file1

    # joins Media::Blob row to Asset row
    Media::Blob.all.each do |blob|
      blob.asset.reference!(blob)
    end
  end

  test "hide new media blob" do
    blob = create :media_blob, repository_network: @source.network
    asset = blob.asset
    asset.reference!(blob)

    assert blob.starter?
    assert_equal [blob], asset.references.map(&:uploadable)
    assert_equal [], asset.archives

    assert_equal false, blob.archive
    assert_nil Media::Blob.find_by(id: blob.id)
    assert_equal [asset.archives.reload.first], asset.references.reload.map(&:uploadable)
  end

  test "archive verified media blob with asset" do
    asset = @source_blob_1.asset
    assert @source_blob_1.verified?
    assert_equal [@source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.map(&:uploadable).sort_by(&:cache_key)
    assert_equal [], asset.archives

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    @source_blob_1.reload
    assert_equal 5.gigabytes, @source_blob_1.send(:max_blob_size)

    assert_equal true, @source_blob_1.archive
    assert archive = asset.archives.reload.first
    assert @source_blob_1.archived?
    assert_equal [archive, @source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.reload.map(&:uploadable).sort_by(&:cache_key)

    blob = Media::Blob.upload(@source, asset.oid,
      size: asset.size,
      pusher: @owner
    )

    assert_equal @source_blob_1, blob

    @source_blob_1.reload
    assert @source_blob_1.saved?
    assert_equal [@source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.reload.map(&:uploadable).sort_by(&:cache_key)
    assert_equal [], asset.archives.reload
  end

  test "archive verified media blob with storage blob" do
    GitHub.stubs(:storage_cluster_enabled?).returns(true)

    blob = create(:media_blob,
      storage_blob: create(:storage_blob, size: 5.gigabytes),
      repository_network: @source.network,
      state: :verified,
    )

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    blob.reload
    assert_equal 5.gigabytes, blob.send(:max_blob_size)

    assert_equal true, blob.archive
    blob.reload
    assert blob.archived?
  end

  test "archive archived media blob" do
    blob = create :media_blob, repository_network: @source.network, state: :archived
    asset = blob.asset
    asset.reference!(blob)

    assert blob.archived?
    assert_equal [blob], asset.references.map(&:uploadable)
    assert_equal [], asset.archives

    assert_equal false, blob.archive
    assert blob.reload.archived?
    assert_equal blob, Media::Blob.find_by(id: blob.id)
    assert_equal [blob], asset.references.reload.map(&:uploadable)
    assert_equal [], asset.archives.reload
  end

  test "unarchive new media blob" do
    blob = create :media_blob, repository_network: @source.network
    asset = blob.asset
    asset.reference!(blob)

    assert blob.starter?
    assert_equal [blob], asset.references.map(&:uploadable)
    assert_equal [], asset.archives

    assert_equal false, blob.unarchive
    assert blob.reload.starter?
    assert_equal [blob], asset.references.map(&:uploadable)
    assert_equal [], asset.archives
  end

  test "unarchive verified media blob" do
    asset = @source_blob_1.asset
    assert @source_blob_1.verified?
    assert_equal [@source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.map(&:uploadable).sort_by(&:cache_key)
    assert_equal [], asset.archives

    assert_equal false, @source_blob_1.unarchive
    assert @source_blob_1.reload.verified?
    assert_equal [@source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.reload.map(&:uploadable).sort_by(&:cache_key)
    assert_equal [], asset.archives.reload

    blob = Media::Blob.upload(@source, asset.oid,
      size: asset.size,
      pusher: @owner
    )

    assert_equal @source_blob_1, blob

    @source_blob_1.reload
    assert @source_blob_1.verified?
    assert_equal [@source_blob_1, @org_blob_2].sort_by(&:cache_key), asset.references.reload.map(&:uploadable).sort_by(&:cache_key)
    assert_equal [], asset.archives.reload
  end

  test "unarchive archived media blob with asset" do
    asset = create :asset, size: 5.gigabytes
    blob = create :media_blob, asset: asset, repository_network: @source.network, state: :archived
    asset.archive!(blob)
    assert archive = asset.archives.reload.first

    assert blob.archived?
    assert_equal [archive], asset.references.map(&:uploadable)
    assert_equal [archive], asset.archives

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    blob.reload
    assert_equal 5.gigabytes, blob.send(:max_blob_size)

    assert_equal true, blob.unarchive
    assert blob.reload.verified?
    assert_equal [blob], asset.references.reload.map(&:uploadable)
    assert_equal [], asset.archives.reload
  end

  test "unarchive archived media blob without asset" do
    blob = create :media_blob, repository_network: @source.network, state: :archived
    blob.asset.archive!(blob)
    Asset.delete_all
    Asset::Reference.delete_all

    assert blob.archived?

    # reload blob to reset the #asset assocation
    assert_equal false, Media::Blob.find(blob.id).unarchive
    assert_nil Media::Blob.find_by(id: blob.id)
  end

  test "unarchive archived media blob with storage blob" do
    GitHub.stubs(:storage_cluster_enabled?).returns(true)

    blob = create(:media_blob,
      storage_blob: create(:storage_blob, size: 5.gigabytes),
      repository_network: @source.network,
      state: :verified,
    )

    assert blob.verified?

    assert_equal true, blob.archive, "archive"
    assert blob.archived?

    result = Billing::ChangeSubscription.perform @owner, plan: "free", actor: @owner
    perform_enqueued_jobs(only: [RunPendingPlanChangeJob])
    assert result.success?

    @owner.reload
    if GitHub.billing_enabled?
      assert_equal 2.gigabytes, @owner.plan_limit(:media_blob_max_size)
    else
      assert_equal 5.gigabytes, @owner.plan_limit(:media_blob_max_size)
    end

    blob.reload
    assert_equal 5.gigabytes, blob.send(:max_blob_size)

    assert_equal true, blob.unarchive, "unarchive"
    assert blob.verified?
  end

  test "builds alambic_absolute_local_path" do
    skip unless GitHub.enterprise? && !GitHub.storage_cluster_enabled?

    blob = @source_blob_1
    oid = blob.oid
    oidpath = "#{oid[0...2]}/#{oid[2...4]}/#{oid}"
    assert_equal "#{GitHub.storage_legacy_path}/media/#{blob.repository_network_id}/#{oidpath}",
      blob.alambic_absolute_local_path
  end

  context "lfs_repositories_for_owner" do
    test "finds the users/orgs lfs repositories" do
      org = create(:organization)
      user = create(:user)
      repo = create(:repository, owner: user, name: "ABC")
      repo2 = create(:repository, owner: user, name: "BCD")
      org_repo = create(:repository, owner: org)
      org_repo2 = create(:repository, owner: org)

      create(:media_blob, repository_network_id: repo.network_id, state: :verified)
      create(:media_blob, repository_network_id: repo2.network_id, state: :verified)
      create(:media_blob, repository_network_id: org_repo.network_id, state: :verified)

      assert_same_elements ::Media::Blob.lfs_repositories_for_owner(user), [repo, repo2]
      assert_equal ::Media::Blob.lfs_repositories_for_owner(org), [org_repo]
    end

    test "doesn't show duplicate repositories" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "ABC")

      create_list(:media_blob, 2, repository_network_id: repo.network_id, state: :verified)
      user_repos = ::Media::Blob.lfs_repositories_for_owner(user)

      assert_equal [repo], user_repos
    end

    test "resolves to an empty array for accounts with no repos using LFS" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "ABC")

      repos = ::Media::Blob.lfs_repositories_for_owner(user)

      assert_equal [], repos
    end
  end
end
