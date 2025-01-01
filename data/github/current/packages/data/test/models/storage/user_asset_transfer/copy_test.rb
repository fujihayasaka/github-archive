# typed: true
# frozen_string_literal: true

require "test_helper"

class TestCopy < Storage::UserAssetTransfer::Copy

end

class TestCopyWithUnauthorizedActor < TestCopy
  def asset_visible_to_actor?(assets)
    Promise.resolve(false)
  end
end

class StorageUserAssetCopyTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @user = create(:user)
    @rando = create(:user)
    @repo = create(:repository)
    @proj = create(:memex_project, owner: @user)
    enable_feature_flag(:secure_user_assets_auth_check)
  end

  setup do
    @s3_client = Aws::S3::Client.new(stub_responses: true)

    GitHub.stubs(:s3_primary_client).returns(@s3_client)
    GitHub.stubs(:s3_production_data_client).returns(@s3_client)
    GitHub.stubs(:memory_alpha_client).returns(@s3_client)
    GitHub.s3_uploads_enabled = true
    GitHub.storage_cluster_enabled = false
  end
  def get_private_saved_reply_asset_url(asset)
    return "https://github.com/user-attachments/assets/#{asset.guid}" if asset.using_new_url?
    "https://github.com/settings/replies/assets/#{asset.user_id}/#{asset.guid}"
  end
  context "#self.copy_by_url" do
    test "returns empty array if empty array is given" do
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([])
      assert_equal 0, actual_translations.length

      actual_copies = UserAsset.all
      assert_equal 0, actual_translations.length
      assert_equal 0, actual_copies.length
    end
    test "returns empty array if given url is not a assets url" do
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([
        "https://github.com/settings"
      ])
      assert_equal 0, actual_translations.length

      actual_copies = UserAsset.all
      assert_equal 0, actual_translations.length
      assert_equal 0, actual_copies.length
    end
    test "returns empty array if no assets found" do
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([
        "https://github.com/settings/replies/assets/1/test-guid"
      ])
      actual_copies = UserAsset.all
      assert_equal 0, actual_translations.length
      assert_equal 0, actual_copies.length
    end
    test "copies to repository if asset found" do
      asset = create(:user_asset, user_id: @user, upload_container_type: @user.class.name, upload_container_id: @user.id, storage_blob_id: 1)
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([get_private_saved_reply_asset_url(asset)])
      actual_copies = UserAsset.where(repository_id: @repo.id, upload_container_type: @repo.class.name, upload_container_id: @repo.id)
      assert_equal 1, actual_translations.length
      assert_equal 1, actual_copies.length
      assert_equal asset.storage_blob_id, T.must(actual_copies.first).storage_blob_id
      assert_equal asset.storage_policy.asset_hash[:href], actual_translations.first&.original
      assert_equal "#{GitHub.url}/user-attachments/assets/#{actual_copies[0].guid}", actual_translations.first&.translation
    end
    test "copies to project if asset found" do
      asset = create(:user_asset, user_id: @user, upload_container_type: @user.class.name, upload_container_id: @user.id, storage_blob_id: 1)
      actual_translations = TestCopy.new(@proj, @user).copy_by_urls([get_private_saved_reply_asset_url(asset)])
      actual_copies = UserAsset.where(upload_container_type: @proj.class.name, upload_container_id: @proj.id)
      assert_equal 1, actual_translations.length
      assert_equal 1, actual_copies.length
      assert_equal asset.storage_blob_id, T.must(actual_copies.first).storage_blob_id
      assert_equal asset.storage_policy.asset_hash[:href], actual_translations.first&.original
      assert_equal "#{@proj.private_asset_url(actual_copies[0].user_id, actual_copies[0].guid, actual_copies[0].using_new_url?)}", actual_translations.first&.translation
    end
    test "copies old-style asset url" do
      UserAsset.any_instance.stubs(:set_url_flag)
      asset = create(:user_asset, user_id: @user, upload_container_type: @user.class.name, upload_container_id: @user.id, storage_blob_id: 1)
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([get_private_saved_reply_asset_url(asset)])
      actual_copies = UserAsset.where(repository_id: @repo.id, upload_container_type: @repo.class.name, upload_container_id: @repo.id)
      assert_equal 1, actual_translations.length
      assert_equal 1, actual_copies.length
      assert_equal asset.storage_blob_id, actual_copies.first!.storage_blob_id
      assert_equal asset.storage_policy.asset_hash[:href], actual_translations.first&.original
      assert_equal "#{@repo.permalink}/assets/#{actual_copies[0].user_id}/#{actual_copies[0].guid}", actual_translations.first&.translation
    end
    test "returns unique translations if the same url is given multiple times" do
      asset = create(:user_asset, user_id: @user, upload_container_type: @user.class.name, upload_container_id: @user.id, storage_blob_id: 1)
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([
        get_private_saved_reply_asset_url(asset),
        get_private_saved_reply_asset_url(asset),
        ])
      actual_copies = UserAsset.where(repository_id: @repo.id, upload_container_type: @repo.class.name, upload_container_id: @repo.id)
      assert_equal 1, actual_translations.length
      assert_equal 1, actual_copies.length
      assert_equal asset.storage_blob_id, T.must(actual_copies.first).storage_blob_id
      assert_equal asset.storage_policy.asset_hash[:href], actual_translations.first&.original
      assert_equal "#{GitHub.url}/user-attachments/assets/#{actual_copies[0].guid}", actual_translations.first&.translation
    end
    test "does not return translations for unauthorized assets" do
      asset = create(:user_asset, user_id: @rando, upload_container_type: @rando.class.name, upload_container_id: @rando.id, storage_blob_id: 1)
      actual_translations = TestCopyWithUnauthorizedActor.new(@repo, @user).copy_by_urls([get_private_saved_reply_asset_url(asset)])
      assert_equal 0, actual_translations.length

      all_assets = UserAsset.all
      actual_copies = UserAsset.where(repository_id: @repo.id, upload_container_type: @repo.class.name, upload_container_id: @repo.id)
      assert_equal 0, actual_copies.length
      assert_equal 1, all_assets.length
    end
    test "purges failed assets and returns error translation" do
      succes_asset = create(:user_asset, user_id: @rando, upload_container_type: @rando.class.name, upload_container_id: @rando.id, storage_blob_id: 1)
      failed_asset = create(:user_asset, user_id: @rando, upload_container_type: @rando.class.name, upload_container_id: @rando.id, storage_blob_id: 2)
      call_count = 0
      ## Stub out  s3_client the copy method to fail on the second call
      @s3_client.stub_responses(:copy_object, -> (_context) {
        call_count += 1
        if call_count == 2
          raise Aws::S3::Errors::ServiceError.new(nil, "Copy failed")
        else
          Aws::S3::Types::CopyObjectResult.new
        end
      })
      actual_translations = TestCopy.new(@repo, @user).copy_by_urls([
        get_private_saved_reply_asset_url(succes_asset),
        get_private_saved_reply_asset_url(failed_asset),
      ])
      assert actual_translations.map(&:translation).include?(
        <<-REPLACEMENT

> [!WARNING]
> This asset could not be copied from your saved reply. Please try again later.

          REPLACEMENT
      )

      all_assets = UserAsset.all
      actual_copies = UserAsset.where(repository_id: @repo.id, upload_container_type: @repo.class.name, upload_container_id: @repo.id)
      assert_equal 1, actual_copies.length
      assert_equal 3, all_assets.length
    end
  end
end
