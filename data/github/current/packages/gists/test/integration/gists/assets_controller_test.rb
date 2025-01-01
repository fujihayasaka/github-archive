# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsAssetsControllerHttpTest < GitHub::IntegrationTestCase
  skip_with_all_emus
  skip_in_multitenant_mode

  fixtures do
    @guid = SecureRandom.uuid
    @user = create(:user)
    @gist = GistHelpers.generate(contents: [{ name: "file.md", value: "test" }], user: @user, public: false)
    @asset = create(:user_asset, user_id: @user, upload_container: @gist, guid: @guid)
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
        GitHub.flipper[:secure_user_assets_auth_check].enable

        expected_s3_redirect_url = @asset.storage_policy.download_url

        get "/gist/user-attachments/assets/#{@asset.guid}"
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
        GitHub.flipper[:secure_user_assets_auth_check].enable
        @asset.update!(using_new_url: nil) # ensures we create a legacy asset

        expected_s3_redirect_url = @asset.storage_policy.download_url

        get "/gist/assets/#{@asset.user_id}/#{@asset.guid}"
        assert_response 302
        assert_redirected_to expected_s3_redirect_url
      end
    end

    test "returns 404 for non-legacy asset" do
      # secure_user_assets_auth_check is always enabled in Dotcom
      GitHub.flipper[:secure_user_assets_auth_check].enable
      @asset.update!(using_new_url: true)

      get "/gist/assets/#{@asset.user_id}/#{@asset.guid}"
      assert_response 404
    end
  end
end
