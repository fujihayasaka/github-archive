# typed: true
# frozen_string_literal: true

require "test_helper"

class TestTransfer < Storage::UserAssetTransfer::Transfer
  def is_target_public?
    repository.public?
  end

  def transfer_assets(assets)
    assets.update_all(repository_id: repository.id, upload_container_type: nil, upload_container_id: nil)
  end

  def asset_url_translation(user_id, guid, use_new_url)
    return "#{GitHub.url}/user-attachments/assets/#{guid}" if use_new_url
    "#{repository.permalink}/assets/#{user_id}/#{guid}"
  end

  def repository
    T.cast(target, Repository) # rubocop:todo GitHub/AvoidCast
  end
end

class TestTransferWithExtraMatcherCheck < TestTransfer
  def extra_matcher_passed?(path)
    path.match?(/\/custom-matcher\//)
  end
end

class TestTransferWithUnauthorizedActor < TestTransfer
  def asset_visible_to_actor?(assets)
    Promise.resolve(false)
  end
end

class StorageUserAssetTransferTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    GitHub.flipper[:new_user_asset_url].enable
    @user = create(:user)
    @pub_repo = create(:repository, owner: @user)
    @priv_repo = create(:private_repository, owner: @user)
  end

  def described_class(target)
    TestTransfer.new(target, @user)
  end

  def create_asset_url_for_transfer(asset)
    return "https://github.com/user-attachments/assets/#{asset.guid}" if asset.using_new_url?
    "https://github.com/some/path/to/assets/#{asset.user_id}/#{asset.guid}"
  end

  context "#self.extract_urls_from_text" do
    test "returns empty array if text is nil" do
      assert_equal [], Storage::UserAssetTransfer::Transfer.extract_urls_from_text(nil)
    end

    test "returns empty array if text doesn't contain any urls" do
      assert_equal [], Storage::UserAssetTransfer::Transfer.extract_urls_from_text("some text")
    end

    test "returns array of uniq urls" do
      text = <<-TEXT
        Hello, this is a text with some urls:

        ![image](http://example.com/image.png)
        ![image](http://example.com/image.png)
        ![image](http://example.com/image.png)

        <img src="http://foobar.com">

        Link: http://someexample.com/pdfs

        Thanks!
      TEXT

      expected_array = ["http://example.com/image.png", "http://foobar.com", "http://someexample.com/pdfs"]

      assert_equal 3, Storage::UserAssetTransfer::Transfer.extract_urls_from_text(text).size
      assert_equal expected_array, Storage::UserAssetTransfer::Transfer.extract_urls_from_text(text)
    end
  end

  context "#transfer_by_urls" do
    test "it moves assets to a repository", skip_in_multitenant_mode: true do
      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project
      asset1 = create(:user_asset, uploader: memex.owner, upload_container: memex)
      asset2 = create(:user_asset, uploader: memex.owner, upload_container: memex)
      assets = [asset1, asset2]

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }
      10.times { urls << create_asset_url_for_transfer(asset1) }

      instance = described_class(@pub_repo)
      instance.expects(:handle_s3_objects).with { |args| assert_same_elements(assets, args) }.once

      translations = instance.transfer_by_urls(urls)

      assert_equal 2, translations.size

      assets.each do |asset|
        asset.reload

        assert_equal @pub_repo.id, asset.repository_id
        assert_equal asset.upload_container, @pub_repo
        translation = translations.find { |t| t.original == create_asset_url_for_transfer(asset) }
        assert_equal translation.translation, "#{GitHub.url}/user-attachments/assets/#{asset.guid}"
      end
    end

    test "it moves assets with legacy urls to a repository", skip_in_multitenant_mode: true do
      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project

      UserAsset.any_instance.stubs(:set_url_flag)
      asset1 = create(:user_asset, uploader: memex.owner, upload_container: memex)
      asset2 = create(:user_asset, uploader: memex.owner, upload_container: memex)
      assets = [asset1, asset2]

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }
      10.times { urls << create_asset_url_for_transfer(asset1) }

      instance = described_class(@pub_repo)
      instance.expects(:handle_s3_objects).with { |args| assert_same_elements(assets, args) }.once

      translations = instance.transfer_by_urls(urls)

      assert_equal 2, translations.size

      assets.each do |asset|
        asset.reload

        assert_equal @pub_repo.id, asset.repository_id
        assert_equal asset.upload_container, @pub_repo
        translation = translations.find { |t| t.original == create_asset_url_for_transfer(asset) }
        assert_equal translation.translation, "#{@pub_repo.permalink}/assets/#{asset.user_id}/#{asset.guid}"
      end
    end

    test "it doesn't transfer to repository if url has wrong format" do
      asset = create(:user_asset, uploader: @user)

      urls = [
        "https://github.com/some/path/to/assets/some/wrong-path",
        "https://notalloweddomain.com/some/path/to/assets/#{asset.user_id}/#{asset.guid}",
        "not a url"
      ]

      UserAsset.expects(:where).never

      instance = described_class(@pub_repo)
      translations = instance.transfer_by_urls(urls)
      assert_equal 0, translations.size
    end

    test "it ignores extra matcher pattern for new-style urls" do
      asset = create(:user_asset, uploader: @user)

      urls = [create_asset_url_for_transfer(asset)]

      instance = TestTransferWithExtraMatcherCheck.new(@pub_repo, @user)
      translations = instance.transfer_by_urls(urls)
      assert_equal 1, translations.size
    end

    test "it doesn't transfer to repository if url path doesn't match to extra matcher pattern" do
      UserAsset.any_instance.stubs(:set_url_flag)
      asset = create(:user_asset, uploader: @user)

      urls = [create_asset_url_for_transfer(asset)]

      UserAsset.expects(:where).never

      instance = TestTransferWithExtraMatcherCheck.new(@pub_repo, @user)
      translations = instance.transfer_by_urls(urls)
      assert_equal 0, translations.size
    end

    test "raises error if actor is not authorized" do
      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project
      assets = create_list(:user_asset, 2, uploader: memex.owner, upload_container: memex)

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }

      instance = TestTransferWithUnauthorizedActor.new(@pub_repo, @user)
      instance.expects(:original_assets_upload_containers_data?).never
      instance.expects(:transfer_assets?).never
      instance.expects(:update_assets_acl).never

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        instance.transfer_by_urls(urls)
      end
    end

    test "it doens't update assets ACL if update_all raises an exception" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)

      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project
      assets = create_list(:user_asset, 2, uploader: memex.owner, upload_container: memex)

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }

      ActiveRecord::Relation.any_instance.stubs(:update_all).raises(Exception)

      instance = described_class(@pub_repo)
      instance.expects(:handle_s3_objects).never

      assert_raises Exception do
        instance.transfer_by_urls(urls)
      end
    end

    test "raises error if the updated count is equal to zero" do
      GitHub.stubs(:multi_tenant_enterprise?).returns(false)

      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project
      assets = create_list(:user_asset, 2, uploader: memex.owner, upload_container: memex)

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }

      ActiveRecord::Relation.any_instance.stubs(:update_all).returns(0)

      instance = described_class(@pub_repo)
      instance.expects(:handle_s3_objects).never

      assert_raises Storage::UserAssetTransfer::Transfer::TransferError do
        instance.transfer_by_urls(urls)
      end
    end

    test "it doens't update assets ACL if in multi tenant" do
      on_multi_tenant_enterprise do
        draft_issue = create(:draft_issue)
        memex = draft_issue.memex_project
        assets = create_list(:user_asset, 2, uploader: memex.owner, upload_container: memex)

        instance = described_class(@pub_repo)
        instance.expects(:handle_s3_objects).never

        urls = assets.map { |asset| create_asset_url_for_transfer(asset) }
        translations = instance.transfer_by_urls(urls)

        assert_equal 2, translations.size

        assets.each do |asset|
          asset.reload

          assert_equal @pub_repo.id, asset.repository_id
          assert_equal asset.upload_container, @pub_repo
          translation = translations.find { |t| t.original == create_asset_url_for_transfer(asset) }
          assert_equal translation.translation, "#{GitHub.url}/user-attachments/assets/#{asset.guid}"
        end
      end
    end

    test "it doens't update assets ACL if storage cluster is enabled", skip_in_multitenant_mode: true do
      GitHub.stubs(:storage_cluster_enabled?).returns(true)
      draft_issue = create(:draft_issue)
      memex = draft_issue.memex_project

      asset1 = save_file_for_uploadable(UserAsset.new(uploader: memex.owner, upload_container: memex))
      asset2 = save_file_for_uploadable(UserAsset.new(uploader: memex.owner, upload_container: memex))
      assets = [asset1, asset2]


      instance = described_class(@pub_repo)
      instance.expects(:handle_s3_objects).never

      urls = assets.map { |asset| create_asset_url_for_transfer(asset) }
      translations = instance.transfer_by_urls(urls)

      assert_equal 2, translations.size

      assets.each do |asset|
        asset.reload

        assert_equal @pub_repo.id, asset.repository_id
        assert_equal asset.upload_container, @pub_repo
        translation = translations.find { |t| t.original == create_asset_url_for_transfer(asset) }
        assert_equal translation.translation, "#{GitHub.url}/user-attachments/assets/#{asset.guid}"
      end
    end
  end
end
