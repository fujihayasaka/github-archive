# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "transfer_test_helper"

class StorageUserAssetDraftToRepositoryTransferTest < GitHub::TestCase
  include TransferTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    @draft = create(:draft_issue)
    @memex_project = @draft.memex_project
    @asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)
  end

  def described_class(repo = nil, user = nil)
    Storage::UserAssetTransfer::DraftToRepositoryTransfer.new(repo || @repo, user || @user)
  end

  context "#extra_matcher_passed?"  do
    test "returns true if asset url passes extra check" do
      uri = described_class.send(:parse_uri, create_draft_asset_url(@asset))
      assert described_class.extra_matcher_passed?(uri.path)
    end

    test "returns false if asset url doesn't pass extra check" do
      uri = described_class.send(:parse_uri, create_unrelated_asset_url(@asset))
      refute described_class.extra_matcher_passed?(uri.path)
    end
  end

  context "#transfer_assets" do
    test "transfers assets to repositoy" do
      asset = create(:user_asset, uploader: @user, upload_container: @repo)
      assets = UserAsset.where(id: asset.id)

      count = described_class.transfer_assets(assets)
      assert_equal 1, count

      asset.reload
      assert_equal @repo.id, asset.repository_id
      assert_equal @repo, asset.upload_container
    end
  end

  context "#is_target_public?" do
    test "returns true" do
      assert described_class.is_target_public?
    end
  end

  context "#asset_url_translation" do
    test "returns old-style translated url for asset" do
      translation = described_class.asset_url_translation(@asset.user_id, @asset.guid, false)
      assert_equal translation, "#{@repo.permalink}/assets/#{@asset.user_id}/#{@asset.guid}"
    end

    test "returns new-style translated url for asset" do
      translation = described_class.asset_url_translation(@asset.user_id, @asset.guid, true)
      assert_equal translation, "#{GitHub.url}/user-attachments/assets/#{@asset.guid}"
    end
  end

  context "#handle_s3_objects" do
    test "it updates the ACL to `public-read` if repository is public" do
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)

      stub_s3_client_call_with_acl("public-read", asset)

      instance = described_class(@repo)
      arr = create_active_record_relation([asset])
      instance.send(:original_assets_upload_containers_data, arr)
      instance.handle_s3_objects(arr)
    end

    test "it updates the ACL to `private` if repository is private" do
      draft = create(:draft_issue)
      memex_project = draft.memex_project
      memex_project.update(public: true)
      repo = create(:private_repository, owner: @user)
      asset = create(:user_asset, uploader: memex_project.owner, upload_container: memex_project)

      stub_s3_client_call_with_acl("private", asset)

      instance = described_class(repo)
      arr = create_active_record_relation([asset])
      instance.send(:original_assets_upload_containers_data, arr)
      instance.handle_s3_objects(arr)
    end

    test "it doesn't update ACL if asset's `storage_provider` is not equal `:s3_production_data`" do
      repo = create(:private_repository, owner: @user)
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)

      Aws::S3::Client.any_instance.stubs(:put_object_acl).never

      instance = described_class(repo)
      arr = create_active_record_relation([asset])
      arr.each { |a| a.storage_provider = nil }
      instance.handle_s3_objects(arr)
    end

    test "it doesn't update ACL if target repository and original upload_container have equal visibilities" do
      repo = create(:private_repository, owner: @user)
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)

      Aws::S3::Client.any_instance.stubs(:put_object_acl).never

      instance = described_class(repo)
      arr = create_active_record_relation([asset])
      instance.send(:original_assets_upload_containers_data, arr)
      instance.handle_s3_objects(arr)
    end
  end

  context "#transfer_by_urls" do
    test "rollback if S3 ACL update raises an error", skip_in_multitenant_mode: true do
      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project
      assets = create_list(:user_asset, 10, uploader: memex.owner, upload_container: memex)

      urls = assets.map { |asset| create_draft_asset_url(asset) }

      instance = described_class(@pub_repo, memex.owner)

      (0..3).each { |i| stub_s3_client_call_with_acl("public-read", assets[i]) }

      Aws::S3::Client.any_instance
        .stubs(:put_object_acl)
        .with(
          acl: "public-read",
          bucket: assets[4].storage_s3_bucket,
          key: assets[4].storage_s3_key(nil)
        )
        .raises(StandardError.new("S3 error"))
        .once

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        instance.transfer_by_urls(urls)
      end

      assert_equal 0, instance.url_translations.size

      assets.each do |asset|
        asset.reload

        assert_nil asset.repository_id
        assert_equal asset.upload_container, memex
      end
    end
  end

  context "#asset_visible_to_actor?" do
    test "returns false if upload_container is nil" do
      asset = create(:user_asset, uploader: @user)
      refute described_class.asset_visible_to_actor?(asset).sync
    end

    test "returns false if upload_container is not a MemexProject" do
      asset = create(:user_asset, uploader: @user, upload_container: @repo)
      refute described_class.asset_visible_to_actor?(asset).sync
    end

    test "returns false if user doesn't have access to MemexProject" do
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)
      refute described_class.asset_visible_to_actor?(asset).sync
    end

    test "returns false if user is nil" do
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)
      instance = Storage::UserAssetTransfer::DraftToRepositoryTransfer.new(@repo, nil)
      refute instance.asset_visible_to_actor?(asset).sync
    end

    test "returns true if user has access to MemexProject" do
      asset = create(:user_asset, uploader: @memex_project.owner, upload_container: @memex_project)
      instance = Storage::UserAssetTransfer::DraftToRepositoryTransfer.new(@repo, @memex_project.owner)
      assert instance.asset_visible_to_actor?(asset).sync
    end
  end
end
