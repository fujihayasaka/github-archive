# typed: true
# frozen_string_literal: true

require "test_helper"

class StorageClusterPolicyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @avatar = Avatar.new(owner: @user, size: 0, content_type: "image/jpg")
  end

  context "generating a download url" do
    test "when a query is passed in the url has it in the query string" do
      @policy = Storage::ClusterPolicy.new(@avatar)
      query = URI.parse(@policy.download_url(some: "query")).query
      assert_equal "some=query", query
    end

    test "when the uploadable has a token, the token is in the query string" do
      @policy = Storage::ClusterPolicy.new(@avatar, actor: @user)
      query = URI.parse(@policy.download_url).query
      assert_match "token=", query
    end

    test "passes down expiration if set and uploadable is UserAsset" do
      expiration = 5.minutes
      user_asset = create(:user_asset, uploader: @user)

      @policy = Storage::ClusterPolicy.new(user_asset, actor: @user)
      user_asset.expects(:storage_cluster_download_token).with(@policy, expires: expiration)

      URI.parse(@policy.download_url(expiration: expiration)).query
    end

    test "doesn't pass down expires if not set and uploadable is UserAsset" do
      user_asset = create(:user_asset, uploader: @user)

      @policy = Storage::ClusterPolicy.new(user_asset, actor: @user)
      user_asset.expects(:storage_cluster_download_token).with(@policy)

      URI.parse(@policy.download_url).query
    end

    test "when the uploadable does not have a token and a query is not passed in, the query string is empty" do
      @policy = Storage::ClusterPolicy.new(@avatar)
      query = URI.parse(@policy.download_url).query
      assert_nil query
    end
  end

  context "stats" do
    test "for download" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Storage::ClusterPolicy.new(@avatar).download_url

      assert stat = stats.timings("storage_policy.url")[0]
      assert_includes stat.tags, "policy:cluster"
      assert_includes stat.tags, "model:avatar"
      assert_includes stat.tags, "op:download"
    end

    test "for upload" do
      stats = GitHub::MemoryDogstatsD.new
      GitHub.stubs(:dogstats).returns(stats)

      Storage::ClusterPolicy.new(@avatar, actor: @user).policy_hash

      assert stat = stats.timings("storage_policy.url")[0]
      assert_includes stat.tags, "policy:cluster"
      assert_includes stat.tags, "model:avatar"
      assert_includes stat.tags, "op:upload"
    end
  end

  context "asset_hash" do
    test "adds upload container data to hash if set" do
      GitHub.storage_cluster_enabled = true
      uploadable = UserAsset.new(user_id: @user.id, upload_container_type: "User", upload_container_id: 1)
      hs = uploadable.storage_policy(actor: @user).policy_hash

      assert_equal hs[:asset][:upload_container_type], "User"
      assert_equal hs[:asset][:upload_container_id], 1

      GitHub.storage_cluster_enabled = false
    end

    test "shoudn't add upload container data to hash if not set" do
      GitHub.storage_cluster_enabled = true
      uploadable = UserAsset.new(user_id: @user.id)
      hs = uploadable.storage_policy(actor: @user).policy_hash

      assert_nil hs[:asset][:upload_container_type]
      assert_nil hs[:asset][:upload_container_id]

      GitHub.storage_cluster_enabled = false
    end

    test "shoudn't add upload container id data to hash if upload container type is not set" do
      GitHub.storage_cluster_enabled = true
      uploadable = UserAsset.new(user_id: @user.id, upload_container_id: 1)
      hs = uploadable.storage_policy(actor: @user).policy_hash

      assert_nil hs[:asset][:upload_container_type]
      assert_nil hs[:asset][:upload_container_id]

      GitHub.storage_cluster_enabled = false
    end

    test "adds repository_id data to hash if set" do
      GitHub.storage_cluster_enabled = true
      uploadable = UserAsset.new(user_id: @user.id, repository_id: 1)
      hs = uploadable.storage_policy(actor: @user).policy_hash

      assert_equal hs[:asset][:repository_id], 1

      GitHub.storage_cluster_enabled = false
    end

    test "shouldn't repository_id data to hash if not set" do
      GitHub.storage_cluster_enabled = true
      uploadable = UserAsset.new(user_id: @user.id)
      hs = uploadable.storage_policy(actor: @user).policy_hash

      assert_nil hs[:asset][:repository_id]

      GitHub.storage_cluster_enabled = false
    end
  end
end
