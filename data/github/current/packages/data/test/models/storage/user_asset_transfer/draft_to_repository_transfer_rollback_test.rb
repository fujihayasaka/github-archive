# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "transfer_test_helper"

class StorageUserAssetDraftToRepositoryTransferRollbackTest < GitHub::TestCase
  include TransferTestHelper

  fixtures do
    @unrelated_user = create(:user)
    @user = create(:user)
    @repo = create(:private_repository, owner: @user)
    @draft = create(:draft_issue)
    @memex_project = @draft.memex_project
  end

  def described_class(user = nil)
    Storage::UserAssetTransfer::DraftToRepositoryTransferRollback.new(@memex_project, user || @user)
  end

  context "#rollback" do
    test "transfers assets from repositoy to memex project if actor has access to repositoty" do
      repo = create(:repository, owner: @user)
      asset = create(:user_asset, uploader: @user, repository: repo)
      stub_s3_client_call_with_acl("private", asset) unless GitHub.multi_tenant_enterprise?

      # We want to simulate assets that were moved, but some problem occurred with the issue creation
      assert_equal repo, asset.repository
      assert_equal repo, asset.upload_container

      described_class.rollback(draft_body_with_assets(asset))

      asset.reload
      assert_nil asset.repository
      assert_equal asset.upload_container, @memex_project
    end

    test "it doesn't transfer assets from repositoy to memex project if actor doesn't have access to repositoty" do
      asset = create(:user_asset, uploader: @user, repository: @repo)
      Aws::S3::Client.any_instance.stubs(:put_object_acl).never unless GitHub.multi_tenant_enterprise?

      # We want to simulate assets that were moved, but some problem occurred with the issue creation
      assert_equal @repo, asset.repository
      assert_equal @repo, asset.upload_container

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        described_class(@unrelated_user).rollback(draft_body_with_assets(asset))
      end

      asset.reload
      assert_equal asset.repository, @repo
      assert_equal asset.upload_container, @repo
    end
  end

  context "#is_target_public?" do
    test "returns true" do
      refute described_class.is_target_public?
    end
  end

  context "#asset_url_translation" do
    test "returns empty string" do
      assert_equal "", described_class.asset_url_translation(1, "abcd1234", false)
    end
  end

  context "#asset_visible_to_actor?" do
    test "returns false if repository is nil" do
      asset = create(:user_asset, uploader: @user)
      refute described_class.asset_visible_to_actor?(asset).sync
    end

    test "returns false if user doesn't have access to repository" do
      asset = create(:user_asset, uploader: @user, repository: @repo)
      refute described_class(@unrelated_user).asset_visible_to_actor?(asset).sync
    end

    test "returns false if user is nil" do
      asset = create(:user_asset, uploader: @user, repository: @repo)
      instance = Storage::UserAssetTransfer::DraftToRepositoryTransferRollback.new(@memex_project, nil)
      refute instance.asset_visible_to_actor?(asset).sync
    end

    test "returns true if user has access to MemexProject" do
      asset = create(:user_asset, uploader: @user, repository: @repo)
      assert described_class.asset_visible_to_actor?(asset).sync
    end
  end
end
