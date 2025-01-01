# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsAssetsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus
  skip_in_multitenant_mode

  fixtures do
    enable_feature_flag(:restrict_if_unassociated_assets)
    enable_feature_flag(:restrict_unassociated_user_assets)
    @rando = create(:user)
    @guid = SecureRandom.uuid
    @user = create(:user)
    @gist = GistHelpers.generate(contents: [{ name: "file.md", value: "test" }], user: @user, public: false)
    @asset = create(:user_asset, user_id: @user, upload_container: @gist, guid: @guid)
    @no_attachments_asset = create(:user_asset, user_id: @user, upload_container: @gist, guid: SecureRandom.uuid)
    create(:attachment, attacher: @user, asset: @asset, attachable: @gist)
  end

  context "show" do
    test "returns 404 for missing user asset" do
      get "/gist/user-attachments/assets/missing-guid"
      assert_response 404
    end

    test "returns 404 if upload_container is not a Gist" do
      user = create(:user)
      repo = create(:repository, owner: user)
      asset = create(:user_asset, user_id: user, upload_container: repo)

      get "/gist/user-attachments/assets/#{asset.guid}"
      assert_response 404
    end

    test "returns 302 when user asset is found" do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)

        expected_s3_redirect_url = @asset.storage_policy.download_url

        get "/gist/user-attachments/assets/#{@asset.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end

    test "returns 404 when user asset doesn't have attachment" do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)
        no_attachments_asset = create(:user_asset, user_id: @user, upload_container: @gist, guid: SecureRandom.uuid)
        expected_s3_redirect_url = no_attachments_asset.storage_policy.download_url

        get "/gist/user-attachments/assets/#{no_attachments_asset.guid}"
        assert_response 404
      end
    end

    test "returns 302 when user asset doesn't have attachment but flag is disabled" do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)
        disable_feature_flag(:restrict_unassociated_user_assets)
        expected_s3_redirect_url = @no_attachments_asset.storage_policy.download_url
        as @rando
        get "/gist/user-attachments/assets/#{@no_attachments_asset.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end

    test "returns 302 when user asset doesnt have db flag " do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)
        UserAsset.any_instance.stubs(:set_restrict_if_unassociated_flag)
        asset_without_db_flag = create(:user_asset, user_id: @user, upload_container: @gist, guid: SecureRandom.uuid)
        expected_s3_redirect_url = asset_without_db_flag.storage_policy.download_url
        as @rando
        get "/gist/user-attachments/assets/#{asset_without_db_flag.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end

    test "returns 302 when asset is restricted but viewer is uploader" do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)
        expected_s3_redirect_url = @no_attachments_asset.storage_policy.download_url
        as @user
        get "/gist/user-attachments/assets/#{@no_attachments_asset.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end
  end

  context "GET legacy_show" do
    test "returns 404 for missing user asset" do
      get "/gist/assets/#{@user.id}/missing-guid"
      assert_response 404
    end

    test "returns 404 if upload_container is not a Gist" do
      UserAsset.any_instance.stubs(:set_url_flag) # ensures we create a legacy asset
      user = create(:user)
      repo = create(:repository, owner: user)
      asset = create(:user_asset, user_id: user, upload_container: repo)

      get "/gist/assets/#{user.id}/#{asset.guid}"
      assert_response 404
    end

    test "returns 302 when user asset is found" do
      Timecop.freeze do
        # secure_user_assets_auth_check is always enabled in Dotcom
        enable_feature_flag(:secure_user_assets_auth_check)
        @asset.update!(using_new_url: nil) # ensures we create a legacy asset

        expected_s3_redirect_url = @asset.storage_policy.download_url

        get "/gist/assets/#{@asset.user_id}/#{@asset.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end

    test "returns 404 for non-legacy asset" do
      # secure_user_assets_auth_check is always enabled in Dotcom
      enable_feature_flag(:secure_user_assets_auth_check)
      @asset.update!(using_new_url: true)

      get "/gist/assets/#{@asset.user_id}/#{@asset.guid}"
      assert_response 404
    end
  end
end
