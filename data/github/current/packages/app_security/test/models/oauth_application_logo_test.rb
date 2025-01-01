# typed: true
# frozen_string_literal: true

require "test_helper"

class NewOauthApplicationAssetTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @user  = create(:user)
    @app   = create :oauth_application, user: @user
    @asset = save_file_for_uploadable(OauthApplicationLogo.new(uploader: @user))
  end

  test "pulls content type from upload" do
    assert_equal "image/jpeg", @asset.content_type
  end

  test "pulls size from upload" do
    assert_equal 1.kilobyte, @asset.size
  end

  test "pulls filename from upload" do
    assert_equal "pug.jpeg", @asset.name
  end

  test "sets raw asset uuid" do
    assert_equal @asset, OauthApplicationLogo.find_by(guid: @asset.guid)
  end

  test "builds s3 key" do
    assert_equal "assets/#{@user.id}/#{@asset.id}/#{@asset.guid}.jpeg", @asset.storage_s3_key(@asset.storage_policy)
  end

  test "stores in alambic during create" do
    asset = OauthApplicationLogo.new(uploader: @user)
    assert_predicate asset, :starter?

    save_file_for_uploadable asset

    assert_predicate asset, :uploaded?
  end

  test "storage enterprise policy" do
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    policy = @asset.storage_policy
    assert_kind_of Storage::ClusterPolicy, policy

    ext = UserAsset.asset_extension(@asset)
    assert_match %r{/storage/oauth_logos/#{@asset.guid}(\z|\?)}, @asset.reload.url
    assert_match %r{/storage/oauth_logos/#{@asset.guid}(\z|\?)}, policy.download_link[:href]
  end

  test "storage production policy" do
    GitHub.s3_uploads_enabled = true
    policy = @asset.storage_policy
    assert_kind_of Storage::S3Policy, policy
    assert_equal "public-read", policy.acl

    expected = "/assets/%d/%d/%s%s" % [@user.id, @asset.id, @asset.guid, File.extname(@asset.name)]
    assert_match expected, @asset.reload.url
    assert_match expected, policy.download_link[:href]
  end

  test "when application is set on create, it validates the uploader" do
    # when the uploader is not the application owner
    not_app_owner = create(:user)
    logo = OauthApplicationLogo.new(uploader: not_app_owner, application: @app)
    assert_equal false, logo.valid?
    assert_includes logo.errors.messages, :uploader_id

    # when the uploader is not an admin of the org that owns the application
    org = create(:organization)
    org_app = create :oauth_application, user: org
    logo = OauthApplicationLogo.new(uploader: @user, application: org_app)
    assert_equal false, logo.valid?
    assert_includes logo.errors.messages, :uploader_id
  end
end
