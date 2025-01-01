# typed: false
# frozen_string_literal: true

require "test_helper"

class UserAssetTest < GitHub::TestCase
  include UploadableTestHelpers
  include CdnTestHelper
  include HydroTestHelpers

  fixtures do
    GitHub.flipper[:new_user_asset_url].disable
    @user = create(:user)
    @business_org = create(:enterprise_linked_organization)
    @business_org.add_admin(@user)

    @repo = create :repository, owner: @user, private: TestEnv.test_in_multitenancy_mode?
    @org_repo = create :repository, owner: @business_org

    @asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))
    @asset2 = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))
  end

  setup do
    GitHub.user_images_cdn_url = "https://user-images.githubusercontent.com/"
  end

  teardown do
    GitHub.user_images_cdn_url = nil
  end

  context "#default_scope" do
    test "finds asset if it's not quarantining" do
      asset = create(:user_asset, uploader: @user)
      assert UserAsset.find(asset.id)
    end

    test "doesn't find asset if it's quarantining" do
      asset = create(:user_asset, uploader: @user, quarantining: true)
      assert_raises(ActiveRecord::RecordNotFound) { UserAsset.find(asset.id) }
    end
  end

  context "#quarantined scope" do
    test "finds asset if it's quarantining" do
      asset = create(:user_asset, uploader: @user, quarantining: true)
      assert UserAsset.quarantined.find(asset.id)
    end

    test "doesn't find asset if it's not quarantining" do
      asset = create(:user_asset, uploader: @user)
      assert_raises(ActiveRecord::RecordNotFound) { UserAsset.quarantined.find(asset.id) }
    end
  end

  test "allows content types" do
    ctypes = UserAsset.allowed_content_types
    assert_includes ctypes, "image/gif"
    assert_includes ctypes, "image/png"
    assert_includes ctypes, "image/jpeg"
    assert_includes ctypes, "video/quicktime"
    assert_includes ctypes, "video/mp4"
  end

  test "sanitizes file name" do
    assert_name_sanitization UserAsset
  end

  test "requires matching file extension" do
    asset = UserAsset.new uploader: @user
    errored = false
    begin
      save_file_for_uploadable asset, name: "pug.html", content_type: "image/jpeg"
    rescue ActiveRecord::RecordInvalid => err
      errored = true
      assert err.record.errors[:name]
    end
    assert errored
  end

  test "uploader must be present" do
    subject = UserAsset.create(
      repository: @repo,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors.nil?
  end

  test "repository must exist if repository_id is set" do
    subject = UserAsset.create(
      uploader: @user,
      repository_id: 123123123,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:repository_id].empty?
  end

  test "uploader must have pull access to repository" do
    rando = create(:user)
    secret = create(:private_repository, owner: @user)

    subject = UserAsset.create(
      repository: secret,
      uploader: rando,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:uploader_id].empty?
  end

  test "project must exist if upload_container_type is set and equal to MemexProject" do
    subject = UserAsset.create(
      uploader: @user,
      upload_container_type: MemexProject.name,
      upload_container_id: 123123123,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:upload_container_id].empty?
  end

  test "uploader must have read access to memex project" do
    rando = create(:user)
    secret = create(:memex_project, owner: @user)

    data = {
      upload_container: secret,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42
    }

    subject = UserAsset.create(data.merge(uploader: rando))

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:uploader_id].empty?

    subject = UserAsset.create(data.merge(uploader: @user))

    assert subject.persisted?
    assert subject.valid?
    assert subject.errors[:uploader_id].empty?
  end

  test "user must exist if upload_container_type is set and equal to User" do
    subject = UserAsset.create(
      uploader: @user,
      upload_container_type: User.name,
      upload_container_id: 123123123,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:upload_container_id].empty?
  end

  test "uploader must be equal to upload container when creating a saved reply asset" do
    rando = create(:user)

    data = {
      upload_container: @user,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42
    }

    subject = UserAsset.create(data.merge(uploader: rando))

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:uploader_id].empty?

    subject = UserAsset.create(data.merge(uploader: @user))

    assert subject.persisted?
    assert subject.valid?
    assert subject.errors[:uploader_id].empty?
  end

  test "repository must exist if upload_container_type is set and equal to RepositoryBlob" do
    subject = UserAsset.create(
      uploader: @user,
      upload_container_type: "RepositoryBlob",
      upload_container_id: 123123123,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:upload_container_id].empty?
  end

  test "uploader must have pull access to repository if upload_container_type is set and equal to RepositoryBlob" do
    rando = create(:user)
    secret = create(:private_repository, owner: @user)

    data = {
      upload_container_type: "RepositoryBlob",
      upload_container_id: secret.id,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42
    }

    subject = UserAsset.create(data.merge(uploader: rando))

    refute subject.persisted?
    refute subject.valid?
    refute subject.errors[:uploader_id].empty?

    subject = UserAsset.create(data.merge(uploader: @user))

    assert subject.persisted?
    assert subject.valid?
    assert subject.errors[:uploader_id].empty?
  end

  test "should create asset if uploader doesn't have pull access to repository, but it's importing" do
    GitHub.stubs(:importing?).returns(true)
    rando = create(:user)
    secret = create(:private_repository, owner: @user)

    subject = UserAsset.create(
      repository: secret,
      uploader: rando,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    assert subject.persisted?
    assert subject.valid?
    assert subject.errors[:uploader_id].empty?
  end

  test "repo and upload container can be absent" do
    subject = UserAsset.create(
      uploader: @user,
      name: "test.jpeg",
      content_type: "image/jpeg",
      size: 42)

    assert subject.persisted?
    assert subject.valid?
    assert subject.errors[:uploader_id].empty?
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
    assert_equal @asset, UserAsset.find_by_guid(@asset.guid)
  end

  test "builds s3 key" do
    assert_equal "#{@user.id}/#{@asset.id}-#{@asset.guid}.jpeg", @asset.storage_s3_key(@asset.storage_policy)
  end

  test "finds asset from match by asset id" do
    match = AssetScanner::Match.new(0, @asset.id, nil)
    assert_equal [@asset.id], UserAsset.from_matches([match]).map(&:id)
  end

  test "finds asset from match by asset guid" do
    match = AssetScanner::Match.new(0, nil, @asset.guid)
    assert_equal [@asset], UserAsset.from_matches([match])
  end

  test "finds assets from matches by id and guid" do
    repo = create(:private_repository, owner: @user)
    asset2 = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
    asset3 = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
    asset4 = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))

    matches = [
      AssetScanner::Match.new(0, @asset.id, @asset.guid),
      AssetScanner::Match.new(0, nil, asset2.guid),
      AssetScanner::Match.new(0, asset3.id, nil),
      AssetScanner::Match.new(0, asset4.id, "wrong-guid"),
    ]

    assets = UserAsset.from_matches(matches)
    assert_equal 3, assets.size
    assert_same_elements [@asset.id, asset2.id, asset3.id], assets.map(&:id)
  end

  test "finds unique assets from matches" do
    repo = create(:private_repository, owner: @user)
    asset2 = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
    matches = [
      AssetScanner::Match.new(0, nil, @asset.guid),
      AssetScanner::Match.new(0, @asset.id, nil),
      AssetScanner::Match.new(0, asset2.id, nil)]

    assert_equal [@asset.id, asset2.id], UserAsset.from_matches(matches).map(&:id).sort
  end

  test "sets s3 access private access" do
    assert_equal :private, @asset.storage_s3_access
  end

  test "user assets are accessible if they are not secured", skip_in_multitenant_mode: true do
    GitHub.flipper[:secure_user_assets_auth_check].disable
    repo = create(:private_repository, owner: @user)
    asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
    assert asset.has_access?(@user)

    another_user = create(:user)
    assert asset.has_access?(another_user)
  end


  context "has_access? in multi tenant" do
    test "repository user assets are accessible for authorized users" do
      on_multi_tenant_enterprise do
        GitHub.flipper[:secure_user_assets_auth_check].disable
        repo = create(:private_repository, owner: @user)
        asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
        assert asset.has_access?(@user)

        another_user = create(:user)
        refute asset.has_access?(another_user)
      end
    end

    test "memex user assets are accessible for authorized users" do
      on_multi_tenant_enterprise do
        GitHub.flipper[:secure_user_assets_auth_check].disable
        memex = create(:memex_project, owner: @user)
        project_item = create(:memex_project_item, memex_project: memex)
        draft_issue = create(:draft_issue, memex_project_item: project_item)

        asset = create(:user_asset, uploader: @user, upload_container: draft_issue.memex_project)
        assert asset.has_access?(@user)

        another_user = create(:user)
        refute asset.has_access?(another_user)
      end
    end
  end

  context "for private authed assets" do
    test "repository user assets are accessible for authorized users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      repo = create(:private_repository, owner: @user)
      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: repo))
      assert asset.has_access?(@user)

      another_user = create(:user)
      refute asset.has_access?(another_user)
    end

    test "memex user assets are accessible for authorized users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      memex = create(:memex_project, owner: @user)
      project_item = create(:memex_project_item, memex_project: memex)
      draft_issue = create(:draft_issue, memex_project_item: project_item)

      asset = create(:user_asset, uploader: @user, upload_container: draft_issue.memex_project)
      assert asset.has_access?(@user)

      another_user = create(:user)
      refute asset.has_access?(another_user)
    end

    test "user private (saved replies) user assets are accessible for authorized users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      asset = create(:user_asset, uploader: @user, upload_container: @user)
      assert asset.has_access?(@user)

      another_user = create(:user)
      refute asset.has_access?(another_user)
    end

    test "assets uploaded to gists are accessible for all users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_advisory_uploads].enable
      gist = create(:gist, owner: @user)
      asset = create(:user_asset, uploader: @user, upload_container: gist)

      assert asset.has_access?(@user)
      assert asset.has_access?(@another_user)
    end

    test "assets uploaded to not-yet-created gists are accessible for all users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      asset = create(:user_asset, uploader: @user, upload_container_type: Gist.name)

      assert asset.has_access?(@user)
      assert asset.has_access?(@another_user)
    end

    test "not published repository advisories user assets are only accessible for authorized users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_advisory_uploads].enable
      advisory = create(:repository_advisory, repository: @repo, author: @user, state: "open")
      asset = create(:user_asset, uploader: @user, repository: @repo, upload_container: advisory)
      assert asset.has_access?(@user)

      another_user = create(:user)
      refute asset.has_access?(another_user)

      advisory.add_collaborator(another_user)
      assert asset.has_access?(another_user)
    end

    test "not yet created repository advisories user assets are accessible for authorized users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_advisory_uploads].enable
      asset = create(:user_asset, uploader: @user, upload_container_type: RepositoryAdvisory.name)
      assert asset.has_access?(@user)

      another_user = create(:user)
      refute asset.has_access?(another_user)
    end

    test "published repository advisories user assets are accessible for all users" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_advisory_uploads].enable
      advisory = create(:repository_advisory, repository: @repo, author: @user, state: "published")
      asset = create(:user_asset, uploader: @user, upload_container: advisory)

      another_user = create(:user)
      assert asset.has_access?(another_user)
    end

    test "not published repository advisories user assets are accessible for all users when feature flag is disabled for asset uploader" do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      @user.enable_feature(:secured_advisory_uploads)
      advisory = create(:repository_advisory, repository: @repo, author: @user, state: "open")
      asset = create(:user_asset, uploader: @user, repository: @repo, upload_container: advisory)
      another_user = create(:user)

      refute asset.has_access?(another_user)

      @user.disable_feature(:secured_advisory_uploads)

      assert asset.has_access?(another_user)
    end

    test "it sets ACL to private" do
      private_asset = UserAsset.new(uploader: @user)
      assert_equal :private, private_asset.storage_s3_access
    end

    test "storage production policy with public acl for public repo", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_images].disable
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
      GitHub.s3_uploads_enabled = true

      @org_repo.set_visibility(actor: @user, visibility: Repository::PUBLIC_VISIBILITY)
      private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))

      policy = private_asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = ".com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
      assert_match expected, private_asset.reload.url
      assert_match "https://github.com/%s/%s/assets/%d/%s" % [@org_repo.owner.display_login, @org_repo.name, @user.id, private_asset.guid], private_asset.storage_external_url
      assert_match expected, policy.download_link[:href]
    end

    test "storage production policy with private acl for internal repo", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_images].disable
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
      GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"
      GitHub.s3_uploads_enabled = true

      @org_repo.set_visibility(actor: @user, visibility: Repository::INTERNAL_VISIBILITY)
      private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))

      policy = private_asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = ".com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
      assert_match expected, private_asset.reload.url
      assert_match "https://github.com/%s/%s/assets/%d/%s" % [@org_repo.owner.display_login, @org_repo.name, @user.id, private_asset.guid], private_asset.storage_external_url
      assert_match expected, policy.download_link[:href]
    end

    test "storage production policy with private acl for private repo", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_images].disable
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
      GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"
      GitHub.s3_uploads_enabled = true

      @org_repo.set_visibility(actor: @user, visibility: Repository::PRIVATE_VISIBILITY)
      private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))

      policy = private_asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = ".com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
      assert_match expected, private_asset.reload.url
      assert_match "https://github.com/%s/%s/assets/%d/%s" % [@org_repo.owner.display_login, @org_repo.name, @user.id, private_asset.guid], private_asset.storage_external_url
      assert_match expected, policy.download_link[:href]
    end

    test "storage production policy with private asset tied to deleted repo does not have private images domain or private ACL", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_images].disable
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
      GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"
      GitHub.s3_uploads_enabled = true

      @org_repo.set_visibility(actor: @user, visibility: Repository::PRIVATE_VISIBILITY)
      private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))
      @org_repo.destroy

      # Reload asset to clear memoized flag
      private_asset = UserAsset.find(private_asset.id)

      policy = private_asset.storage_policy

      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = ".com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
      assert_match expected, private_asset.reload.url
      assert_match "https://dev-user-images.example.com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)], private_asset.storage_external_url
      assert_match expected, policy.download_link[:href]
    end

    test "storage production policy with private acl for private repo favors private authed images URL when secured_images ff is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable
      GitHub.flipper[:secured_images].enable
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
      GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"
      GitHub.s3_uploads_enabled = true

      @org_repo.set_visibility(actor: @user, visibility: Repository::PRIVATE_VISIBILITY)
      private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))

      policy = private_asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = ".com/%d/%d-%s%s" % [@user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
      assert_match expected, private_asset.reload.url
      assert_match "https://github.com/%s/%s/assets/%d/%s" % [@org_repo.owner.display_login, @org_repo.name, @user.id, private_asset.guid], private_asset.storage_external_url
      assert_match expected, policy.download_link[:href]
    end

    test "storage production policy with private acl in proxima" do
      on_multi_tenant_enterprise do
        GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
        GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"
        GitHub.s3_uploads_enabled = true

        private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @org_repo))

        policy = private_asset.storage_policy
        assert_kind_of Storage::MemoryAlphaPolicy, policy
        assert_equal "private", policy.acl

        expected = "%s/%s/%d/%d-%s%s" % [GitHub.memory_alpha_url, GitHub.s3_user_asset_new_bucket, @user.id, private_asset.id, private_asset.guid, File.extname(private_asset.name)]
        assert_match expected, private_asset.reload.url
        assert_match "https://github.com/%s/%s/assets/%d/%s" % [@org_repo.owner.display_login, @org_repo.name, @user.id, private_asset.guid], private_asset.storage_external_url
        assert_match expected, policy.download_link[:href]
      end
    end
  end

  test "storage enterprise policy with unsecured images", skip_in_multitenant_mode: true do
    GitHub.flipper[:secured_images].disable
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    policy = @asset.storage_policy(actor: @user)
    assert_kind_of Storage::ClusterPolicy, policy

    assert_match %r{/storage/user/#{@user.id}/files/#{@asset.guid}(\z|\?)}, policy.download_link[:href]
  end

  test "storage enterprise policy with secured images", skip_in_multitenant_mode: true do
    GitHub.flipper[:secured_images].enable
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    policy = @asset.storage_policy(actor: @user)
    assert_kind_of Storage::ClusterPolicy, policy

    assert_match %r{/storage/user/#{@user.id}/repository/#{@repo.id}/files/#{@asset.guid}(\z|\?)}, policy.download_link[:href]
  end

  test "with_storage_provider (default)" do
    u = UserAsset.new
    assert_equal :default, u.storage_provider
    u.with_storage_provider(:s3_production_data) do
      assert_equal :s3_production_data, u.storage_provider
    end
    assert_equal :default, u.storage_provider
  end

  test "with_storage_provider (s3_production_data)" do
    u = UserAsset.new(storage_provider: "s3_production_data")
    assert_equal :s3_production_data, u.storage_provider
    u.with_storage_provider(:default) do
      assert_equal :default, u.storage_provider
    end
    assert_equal :s3_production_data, u.storage_provider
  end

  test "storage production policy" do
    GitHub.flipper[:secured_images].enable
    GitHub.s3_uploads_enabled = true
    policy = @asset.storage_policy
    assert_kind_of Storage::S3Policy, policy
    assert_equal "private", policy.acl

    if TestEnv.test_in_multitenancy_mode?
      expected = "%s/%s/%d/%d-%s%s" % [GitHub.memory_alpha_url, GitHub.s3_user_asset_new_bucket, @user.id, @asset.id, @asset.guid, File.extname(@asset.name)]
    else
      expected = ".com/%d/%d-%s%s" % [@user.id, @asset.id, @asset.guid, File.extname(@asset.name)]
    end

    assert_match expected, @asset.reload.url
    assert_match expected, policy.download_link[:href]
  end

  test "purge deletes attachments and purges cdn when url is a canonical url", skip_in_multitenant_mode: true do
    GitHub.s3_uploads_enabled = true
    GitHub.storage_cluster_enabled = false
    # force feature flag to be enabled so that the generated url is a canonical url
    GitHub.flipper[:secure_user_assets_auth_check].enable
    GitHub.private_user_images_cdn_url = "https://private-user-images.example.com"
    GitHub.user_images_cdn_url = "https://dev-user-images.example.com/"

    issue = create(:issue, repository: @repo, user: @user)
    attachment = Attachment.create!(attacher: @user, asset: @asset,
      attachable: issue, entity: @repo)

    assert_equal attachment, Attachment.find_by_id(attachment.id)
    assert_equal 1, @asset.attachments.count

    deletions = [
      {
        uploadable: @asset,
        bucket: @asset.storage_s3_bucket,
        path: "/#{@asset.storage_s3_key(nil)}",
      },
    ]

    purging_urls = [
      "#{GitHub.user_images_cdn_url}#{@user.id}/#{@asset.id}-#{@asset.guid}#{File.extname(@asset.name)}",
      "#{GitHub.private_user_images_cdn_url}/#{@user.id}/#{@asset.id}-#{@asset.guid}#{File.extname(@asset.name)}",
    ]

    @asset.with_storage_provider(:default) do
      # assert reqs against old s3/fastly domains
      deletions << {
        uploadable: @asset,
        bucket: @asset.storage_s3_bucket,
        path: "/#{@asset.storage_s3_key(nil)}",
      }
      purging_urls << @asset.storage_external_url
    end

    assert_storage_policy_delete_multiple(deletions) do
      assert_purge_url(*purging_urls) do
        @asset.purge
      end
    end

    assert_nil Attachment.find_by_id(attachment.id)
  end

  test "purge deletes attachments in proxima" do
    on_multi_tenant_enterprise do
      GitHub.s3_uploads_enabled = true
      GitHub.storage_cluster_enabled = false

      issue = create(:issue, repository: @repo, user: @user)
      attachment = Attachment.create!(attacher: @user, asset: @asset,
        attachable: issue, entity: @repo)

      assert_equal attachment, Attachment.find_by_id(attachment.id)
      assert_equal 1, @asset.attachments.count

      assert_enqueued_jobs(0, only: [PurgeFastlyUrlJob]) do
        @asset.purge
      end

      assert_nil Attachment.find_by_id(attachment.id)
    end
  end

  test "purge deletes attachments in storage cluster mode", skip_in_multitenant_mode: true do
    GitHub.s3_uploads_enabled = false
    GitHub.storage_cluster_enabled = true

    issue = create(:issue, repository: @repo, user: @user)
    attachment = Attachment.create!(attacher: @user, asset: @asset,
      attachable: issue, entity: @repo)

    assert_equal attachment, Attachment.find_by_id(attachment.id)
    assert_equal 1, @asset.attachments.count

    assert_enqueued_jobs(0, only: [PurgeFastlyUrlJob]) do
      @asset.purge
    end

    assert_nil Attachment.find_by_id(attachment.id)
  end

  context "size validation" do
    context "for non-video assets" do
      test "fails when size is not present" do
        assert_raises ActiveRecord::RecordInvalid do
          save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), content_type: "image/jpeg", size: nil)
        end
      end

      test "fails when size exceeds 10MB" do
        assert_raises ActiveRecord::RecordInvalid do
          save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), content_type: "image/jpeg", size: 11.megabytes)
        end
      end

      test "succeeds when size is within 10MB threshold" do
        assert save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), content_type: "image/jpeg", size: 10.megabytes)
      end
    end

    context "for video assets" do
      test "fails when size is not present" do
        assert_raises ActiveRecord::RecordInvalid do
          save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), name: "video.mp4", content_type: "video/mp4", size: nil)
        end
      end

      test "fails when size exceeds 100MB" do
        assert_raises ActiveRecord::RecordInvalid do
          save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), name: "video.mp4", content_type: "video/mp4", size: 101.megabytes)
        end
      end

      test "succeeds when size is within 100MB threshold" do
        assert save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), name: "video.mp4", content_type: "video/mp4", size: 100.megabytes)
      end
    end
  end

  context "#instrument_user_assets_batch_scan" do
    test "performs an audit log when a batch scan is triggered" do
      staff_user = create(:staff_admin_user)
      events = subscribe "user_asset.batch_scan"

      payload = {
          action: "user_assets.batch_scan",
          staff_actor: staff_user.display_login,
          staff_actor_id: staff_user.id,
          actor: "github-staff",
          user: @user.display_login,
          user_id: @user.id,
          number_of_assets: @user.assets.count
      }

      UserAsset.instrument_user_assets_batch_scan(payload)

      expected_payload = {
          action: "user_assets.batch_scan",
          staff_actor: staff_user.display_login,
          staff_actor_id: staff_user.id,
          actor: "github-staff",
          user: @user.display_login,
          user_id: @user.id,
          number_of_assets: @user.assets.count
      }

      assert event = events.pop, "an event was expected"

      assert_equal expected_payload, event.payload
    end
  end

  if GitHub.s3_uploads_enabled?
    context "when the asset is an image" do
      test "with the main feature flag on, publishes a UserAssetCreate and a UserAssetScan event to hydro" do
        GitHub.flipper[:schaefer_instrument_upload].enable(@user)
        reset_hydro
        ip_address = "1.2.3.4"
        GitHub.context.push(actor_ip: ip_address)
        user_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))

        assert user_asset.send(:image_content?)
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
        }, schema: "github.v1.UserAssetCreate")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
          upload_ip: Hydro::EntitySerializer.ip_address(ip_address),
        }, schema: "github.v1.UserAssetScan")
      end

      test "with the main feature flag off, only publishes a UserAssetCreate event to hydro" do
        GitHub.flipper[:schaefer_instrument_upload].disable
        reset_hydro
        user_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))

        assert user_asset.send(:image_content?)
        refute_hydro_messages(schema: "github.v1.UserAssetScan")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
        }, schema: "github.v1.UserAssetCreate")
      end
    end

    context "when the asset is a video" do
      test "with the video feature flag on, publishes a UserAssetCreate and a UserAssetScan event to hydro" do
        GitHub.flipper[:schaefer_instrument_video_upload].enable(@user)
        reset_hydro
        ip_address = "1.2.3.4"
        GitHub.context.push(actor_ip: ip_address)
        user_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), name: "example.mp4", content_type: "video/mp4")

        assert user_asset.send(:video_content?)
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
        }, schema: "github.v1.UserAssetCreate")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
          upload_ip: Hydro::EntitySerializer.ip_address(ip_address),
        }, schema: "github.v1.UserAssetScan")
      end

      test "with the video feature flag off, only publishes a UserAssetCreate event to hydro" do
        GitHub.flipper[:schaefer_instrument_video_upload].disable
        reset_hydro
        user_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo), name: "example.mp4", content_type: "video/mp4")

        assert user_asset.send(:video_content?)
        refute_hydro_messages(schema: "github.v1.UserAssetScan")
        assert_hydro_published({
          actor: Hydro::EntitySerializer.user(@user),
          user_asset: Hydro::EntitySerializer.user_asset(user_asset),
        }, schema: "github.v1.UserAssetCreate")
      end
    end
  end

  context "#subset_without_known_photo_dna_hits" do
    test "returns asset given if it's not a known hit" do
      assert_equal [@asset], UserAsset.subset_without_known_photo_dna_hits([@asset])
    end

    test "excludes the hit if there is one" do
      create(:photo_dna_hit, content: @asset)
      assert_equal [@asset2], UserAsset.subset_without_known_photo_dna_hits([@asset, @asset2])
    end
  end

  context "#legacy_storage_external_url" do
    test "returns legacy url when asset created_at < UserAsset::PRIVATE_IMAGES_FEATURE_FLAG_TIMESTAMP" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))
      asset.created_at = Time.find_zone("UTC").parse("2023-05-09T10:03:00.000Z")
      legacy_storage_url = GitHub.user_images_cdn_url + asset.storage_s3_key(asset.storage_policy)

      assert_equal legacy_storage_url, asset.legacy_storage_external_url
    end

    test "returns nil when asset created_at > UserAsset::PRIVATE_IMAGES_FEATURE_FLAG_TIMESTAMP" do
      GitHub.stubs(:enterprise?).returns(false) # rubocop:todo GitHub/DontStubEnterpriseInTests

      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))

      assert_nil asset.legacy_storage_external_url
    end

    context "in GHES" do
      test "returns nil legacy url" do
        GitHub.stubs(:enterprise?).returns(true) # rubocop:todo GitHub/DontStubEnterpriseInTests

        asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))

        assert_nil asset.legacy_storage_external_url
      end
    end
  end

  context "#source_url" do
    test "returns the storage_external_url when storage cluster is enabled" do
      GitHub.stubs(:storage_cluster_enabled?).returns(true)
      GitHub.flipper[:secured_images].enable

      assert_equal @asset.source_url(actor: @user), @asset.storage_external_url
    end

    test "returns the storage_external_url when repository is nil", skip_in_multitenant_mode: true do
      GitHub.stubs(:storage_cluster_enabled?).returns(false)
      GitHub.flipper[:secured_images].enable
      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: nil))

      assert_equal asset.source_url(actor: @user), asset.storage_external_url
    end

    test "returns the storage_external_url when feature flag is disabled" do
      GitHub.stubs(:storage_cluster_enabled?).returns(false)
      GitHub.flipper[:secured_images].disable

      assert_equal @asset.source_url(actor: @user), @asset.storage_external_url
    end

    test "returns the redirect_url", skip_in_multitenant_mode: true do
      GitHub.secured_user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
      GitHub.stubs(:storage_cluster_enabled?).returns(false)
      GitHub.flipper[:secured_images].enable
      GitHub.flipper[:secure_user_assets_auth_check].disable

      # The query params include credentials and may be different for the two urls.
      # We cannot memoize the `redirect_url` because the credentials will expire at some point.
      # This tests the origin (i.e. `https://user-images-cdn.githubusercontent.com/`) and
      # the path (i.e. `/613/20-49a20480-6d53-11eb-8e95-99eb77d2fcef.jpeg`), which notes
      # the source and the asset guid, without comparing the query params.
      source_uri = Addressable::URI.parse(@asset.source_url(actor: @user))
      redirect_uri = Addressable::URI.parse(@asset.redirect_url(actor: @user))

      assert_equal source_uri.origin, redirect_uri.origin
      assert_equal source_uri.path, redirect_uri.path

      assert_equal "300", redirect_uri.query_values["X-Amz-Expires"]
    end

    test "returns the redirect_url with custom expiration", skip_in_multitenant_mode: true do
      GitHub.secured_user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
      GitHub.stubs(:storage_cluster_enabled?).returns(false)
      GitHub.flipper[:secured_images].enable
      GitHub.flipper[:secure_user_assets_auth_check].disable

      @repo = create(:private_repository, owner: @user)
      @private_asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))

      # The query params include credentials and may be different for the two urls.
      # We cannot memoize the `redirect_url` because the credentials will expire at some point.
      # This tests the origin (i.e. `https://user-images-cdn.githubusercontent.com/`) and
      # the path (i.e. `/613/20-49a20480-6d53-11eb-8e95-99eb77d2fcef.jpeg`), which notes
      # the source and the asset guid, without comparing the query params.
      source_uri = Addressable::URI.parse(@asset.source_url(actor: @user))
      redirect_uri = Addressable::URI.parse(@asset.redirect_url(actor: @user, expiration: 1.hour.second))

      assert_equal source_uri.origin, redirect_uri.origin
      assert_equal source_uri.path, redirect_uri.path

      assert_equal "3600", redirect_uri.query_values["X-Amz-Expires"]
    end

    test "returns the storage_external_url when secured_images and secure_user_assets_auth_check flags are enabled" do
      GitHub.secured_user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
      GitHub.private_user_images_cdn_url = "https://private-user-images.example.com/"
      GitHub.stubs(:storage_cluster_enabled?).returns(false)
      GitHub.flipper[:secured_images].enable
      GitHub.flipper[:secure_user_assets_auth_check].enable

      @asset.repository = create(:private_repository)

      assert_equal @asset.source_url(actor: @user), @asset.storage_external_url
    end

    test "returns the storage_external_url in Proxima" do
      on_multi_tenant_enterprise do
        GitHub.secured_user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
        GitHub.private_user_images_cdn_url = "https://private-user-images.example.com/"
        GitHub.stubs(:storage_cluster_enabled?).returns(false)
        GitHub.flipper[:secured_images].disable
        GitHub.flipper[:secure_user_assets_auth_check].disable

        @asset.repository = create(:private_repository)

        assert_equal @asset.source_url(actor: @user), @asset.storage_external_url
      end
    end
  end

  context ".multiple_target_for_conditional_access" do
    test "returns a map of assets to their conditional access target uploaders" do
      cap_target_map = UserAsset.multiple_target_for_conditional_access([@asset, @asset2])
      assert_equal({ @asset => @asset.uploader, @asset2 => @asset2.uploader }, cap_target_map)
    end
  end

  context "target_for_conditional_access" do
    test "returns the user" do
      assert_equal @asset.target_for_conditional_access, @user
    end

    test "returns :no_target_for_conditional_access" do
      user = create(:user)
      repo = create(:private_repository, owner: user)
      asset = create(:user_asset, uploader: user, repository: repo)
      user.destroy!
      asset.reload
      assert_equal asset.target_for_conditional_access, :no_target_for_conditional_access
    end
  end

  context "async_target_for_conditional_access" do
    test "returns the user" do
      assert_equal @asset.async_target_for_conditional_access.sync, @user
    end

    test "returns :no_target_for_conditional_access" do
      user = create(:user)
      repo = create(:private_repository, owner: user)
      asset = create(:user_asset, uploader: user, repository: repo)
      user.destroy!
      asset.reload
      assert_equal asset.async_target_for_conditional_access.sync, :no_target_for_conditional_access
    end
  end

  context "#storage_external_url" do
    context "when storage_provider is :s3_production_data" do
      test "returns repository url when asset has a Repository attached to it" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_asset_for(:repository)

        stubs = {
          private_authed_image_true: proc do
            asset.stubs(:private_authed_image?).returns(true)
            asset.stubs(:legacy_secured_images?).returns(false)
          end,
          legacy_secured_images_true: proc do
            asset.stubs(:private_authed_image?).returns(false)
            asset.stubs(:legacy_secured_images?).returns(true)
          end,
        }

        stubs.each do |_, stub|
          stub.call
          asset.with_storage_provider(:s3_production_data) do
            assert_equal "#{asset.repository.permalink}/assets/#{asset.user_id}/#{asset.guid}", asset.storage_external_url
          end
        end
      end

      test "returns new repository url when feature flag is enabled" do
        GitHub.flipper[:new_user_asset_url].enable
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_asset_for(:repository)

        stubs = {
          private_authed_image_true: proc do
            asset.stubs(:private_authed_image?).returns(true)
            asset.stubs(:legacy_secured_images?).returns(false)
          end,
          legacy_secured_images_true: proc do
            asset.stubs(:private_authed_image?).returns(false)
            asset.stubs(:legacy_secured_images?).returns(true)
          end,
        }

        stubs.each do |_, stub|
          stub.call
          asset.with_storage_provider(:s3_production_data) do
            assert_equal "#{GitHub.url}/user-attachments/assets/#{asset.guid}", asset.storage_external_url
          end
        end
      end

      test "returns upload container url if its class implements `private_asset_url` method" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)
        expected_url = "https://the-upload-container-asset-url.com"

        asset = create_asset_for(:upload_container)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(true)

        asset.upload_container.stubs(:private_asset_url)
          .with(asset.user_id, asset.guid, false)
          .at_least_once
          .returns(expected_url)

        asset.with_storage_provider(:s3_production_data) do
          assert_equal expected_url, asset.storage_external_url
        end
      end

      test "passes correct args to `private_asset_url` method when feature flag is enabled" do
        GitHub.flipper[:new_user_asset_url].enable
        GitHub.stubs(:storage_cluster_enabled?).returns(false)
        expected_url = "https://the-upload-container-asset-url.com"

        asset = create_asset_for(:upload_container)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(true)

        asset.upload_container.stubs(:private_asset_url)
          .with(asset.user_id, asset.guid, true)
          .at_least_once
          .returns(expected_url)

        asset.with_storage_provider(:s3_production_data) do
          assert_equal expected_url, asset.storage_external_url
        end
      end

      test "returns Gist.private_asset_url if Gist has not been created" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)
        expected_url = "https://the-gist-asset-url.com"

        asset = create(:user_asset, uploader: @user, upload_container_type: Gist.name)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(false)

        Gist.any_instance.stubs(:private_asset_url)
          .with(asset.user_id, asset.guid, false)
          .at_least_once
          .returns(expected_url)

        asset.with_storage_provider(:s3_production_data) do
          assert_equal expected_url, asset.storage_external_url
        end
      end

      test "passes correct args to Gist.private_asset_url if feature flag is enabled" do
        GitHub.flipper[:new_user_asset_url].enable
        GitHub.stubs(:storage_cluster_enabled?).returns(false)
        expected_url = "https://the-gist-asset-url.com"

        asset = create(:user_asset, uploader: @user, upload_container_type: Gist.name)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(false)

        Gist.any_instance.stubs(:private_asset_url)
          .with(asset.user_id, asset.guid, true)
          .at_least_once
          .returns(expected_url)

        asset.with_storage_provider(:s3_production_data) do
          assert_equal expected_url, asset.storage_external_url
        end
      end

      test "returns fallback url if upload container class doesn't implement the `private_asset_url` method" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_asset_for(:upload_container)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(true)

        asset.upload_container.stubs(:respond_to?)
          .with(:private_asset_url)
          .at_least_once
          .returns(false)

        asset.with_storage_provider(:s3_production_data) do
          assert_equal mount_fallback_url(asset.user_id, asset), asset.storage_external_url
        end
      end

      test "returns fallback url if upload container `#class.private_asset_url` returns empty string" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_asset_for(:upload_container)

        asset.stubs(:private_authed_image?).returns(false)
        asset.stubs(:legacy_secured_images?).returns(false)
        asset.stubs(:private_upload_container_asset?).returns(true)

        asset.upload_container.stubs(:respond_to?)
          .with(:private_asset_url)
          .at_least_once
          .returns(true)

        asset.upload_container.stubs(:private_asset_url).at_least_once.returns("")

        asset.with_storage_provider(:s3_production_data) do
          assert_equal mount_fallback_url(asset.user_id, asset), asset.storage_external_url
        end
      end

      test "returns fallback url if neither repository nor upload_container is found" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_raw_asset

        asset.with_storage_provider(:s3_production_data) do
          assert_equal mount_fallback_url(asset.user_id, asset), asset.storage_external_url
        end
      end
    end

    context "when storage_provider is not :s3_production_data" do
      test "returns default url" do
        GitHub.stubs(:storage_cluster_enabled?).returns(false)

        asset = create_raw_asset

        asset.with_storage_provider(:default) do
          assert_equal "#{GitHub.asset_url_host}#{GitHub.asset_base_path}/#{asset.user_id}/#{asset.id}/#{asset.guid}#{File.extname(asset.name)}", asset.storage_external_url
        end
      end
    end
  end

  context "#private_authed_image?" do
    test "it's always true in multi tenant" do
      on_multi_tenant_enterprise do
        GitHub.flipper[:secure_user_assets_auth_check].disable

        asset = create_raw_asset
        assert asset.private_authed_image?
      end
    end

    test "it's true when repository is found and `secure_user_assets_auth_check` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable

      asset = create_asset_for(:repository)
      assert asset.private_authed_image?
    end

    test "it's false when repository is not found and `secure_user_assets_auth_check` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable

      asset = create_raw_asset
      refute asset.private_authed_image?
    end

    test "it's false when repository is found and `secure_user_assets_auth_check` is disabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].disable

      asset = create_asset_for(:repository)
      refute asset.private_authed_image?
    end
  end

  context "#legacy_secured_images?" do
    test "it's true when repository is found and `secured_images` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secured_images].enable

      asset = create_asset_for(:repository)
      assert asset.legacy_secured_images?
    end

    test "it's false when repository is not found and `secured_images` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secured_images].enable

      asset = create_raw_asset
      refute asset.legacy_secured_images?
    end

    test "it's false when repository is found and `secured_images` is disabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secured_images].disable

      asset = create_asset_for(:repository)
      refute asset.legacy_secured_images?
    end
  end

  context "#private_upload_container_asset?" do
    test "it's always true in multi tenant" do
      on_multi_tenant_enterprise do
        GitHub.flipper[:secure_user_assets_auth_check].disable

        asset = create_raw_asset
        assert asset.private_upload_container_asset?
      end
    end

    test "it's true when upload_container is found and `secure_user_assets_auth_check` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable

      asset = create_asset_for(:upload_container)
      assert asset.private_upload_container_asset?
    end

    test "it's false when upload_container is not found and `secure_user_assets_auth_check` is enabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable

      asset = create_raw_asset
      refute asset.private_upload_container_asset?
    end

    test "it's false when upload_container is found but it doesn't respond to :async_owner or owner", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].enable

      asset = create_asset_for(:upload_container)

      asset.upload_container.expects(:respond_to?)
        .with(:async_owner)
        .at_least_once
        .returns(false)

      asset.upload_container.expects(:respond_to?)
        .with(:owner)
        .at_least_once
        .returns(false)

      refute asset.private_upload_container_asset?
    end

    test "it's false when upload_container is found and `secure_user_assets_auth_check` is disabled", skip_in_multitenant_mode: true do
      GitHub.flipper[:secure_user_assets_auth_check].disable

      asset = create_asset_for(:upload_container)
      refute asset.private_upload_container_asset?
    end
  end

  context "#validate_access_to_model" do
    test "it adds error to upload_container_type if model_name is invalid" do
      asset = UserAsset.new
      asset.send(:validate_access_to_model, "invalidtype")
      refute asset.errors[:upload_container_type].empty?
    end
  end

  context "#upload_container" do
    test "returns repository if no upload container" do
      asset = UserAsset.new(uploader: @user, repository: @repo)
      assert asset.upload_container == @repo
    end

    test "returns repository if container type is RepositoryBlob" do
      asset = UserAsset.new(uploader: @user, repository: @repo, upload_container_type: "RepositoryBlob")
      assert asset.upload_container == @repo
    end

    test "correctly returns upload container if present" do
      gist = Gist.new
      asset = UserAsset.new(uploader: @user, upload_container: gist)
      assert asset.upload_container == gist
    end
  end

  context "#using_new_url?" do
    test "returns false without feature flag" do
      GitHub.flipper[:new_user_asset_url].disable
      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))
      assert !asset.using_new_url?
    end

    test "returns true with feature flag" do
      GitHub.flipper[:new_user_asset_url].enable
      asset = save_file_for_uploadable(UserAsset.new(uploader: @user, repository: @repo))
      assert asset.using_new_url?
    end
  end

  def mount_fallback_url(user_id, asset)
    "#{GitHub.user_images_cdn_url}#{user_id}/#{asset.id}-#{asset.guid}#{File.extname(asset.name)}"
  end

  def create_asset_for(container_type)
    user = create(:user)
    repo = create(:private_repository, owner: user)
    return create(:user_asset, uploader: user, upload_container: repo) if container_type == :upload_container

    create(:user_asset, uploader: user, repository: repo)
  end

  def create_raw_asset
    user = create(:user)
    create(:user_asset, uploader: user)
  end
end
