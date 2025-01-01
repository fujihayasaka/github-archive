# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "transfer_test_helper"

class StorageUserAssetRepositoryToRepositoryTransferTest < GitHub::TestCase
  include TransferTestHelper
  include UploadableTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:user)
    @from_repo = create(:repository, owner: @owner)
    @to_repo = create(:repository, owner: @owner)
    @asset = create(:user_asset, uploader: @owner, upload_container: @from_repo)
  end

  def create_asset_url_for_transfer(asset)
    return "https://github.com/user-attachments/assets/#{asset.guid}" if asset.using_new_url?
    "https://github.com/some/path/to/assets/#{asset.user_id}/#{asset.guid}"
  end

  test "transfers assets to repository" do
    assets = UserAsset.where(id: @asset.id)
    urls = assets.map { |asset| create_asset_url_for_transfer(asset) }

    updated_assets = Storage::UserAssetTransfer::RepositoryToRepositoryTransfer.transfer_by_urls(@from_repo, @to_repo, @owner, urls)
    assert_equal 1, updated_assets.size

    @asset.reload
    assert_equal @to_repo.id, @asset.repository_id
    assert_equal @to_repo, @asset.upload_container
  end

  test "throws when user does not have permissions on one asset" do
    random_user = create(:user)
    random_repo = create(:repository, owner: random_user)
    random_asset = create(:user_asset, uploader: random_user, upload_container: random_repo)
    urls = UserAsset.where(id: random_asset.id).map { |asset| create_asset_url_for_transfer(asset) }

    assert_raises_with_message Storage::UserAssetTransfer::Transfer::TransferError, "Actor is not authorized to transfer some of the assets" do
      Storage::UserAssetTransfer::RepositoryToRepositoryTransfer.transfer_by_urls(@from_repo, @to_repo, @owner, urls)
    end
  end

  test "throws when asset doesn't belong to origin repo, regardless of actor permissions" do
    another_repo = create(:repository, owner: @owner)
    asset = create(:user_asset, uploader: @owner, upload_container: another_repo)
    urls = UserAsset.where(id: asset.id).map { |asset| create_asset_url_for_transfer(asset) }

    assert_raises_with_message Storage::UserAssetTransfer::Transfer::TransferError, "Actor is not authorized to transfer some of the assets" do
      Storage::UserAssetTransfer::RepositoryToRepositoryTransfer.transfer_by_urls(@from_repo, @to_repo, @owner, urls)
    end
  end
end
