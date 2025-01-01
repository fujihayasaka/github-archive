# typed: false
# frozen_string_literal: true

require "test_helper"

class AvatarTest < GitHub::TestCase
  include CdnTestHelper
  include UploadableTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @meta = { size: 42, content_type: "image/png", width: 5, height: 6 }
    @asset = create(:asset)
    @cropped_asset = create :asset, width: 150, height: 100
    @owner = create :user, login: "owner"
    @org = create :organization, login: "org", admin: @owner
    @avatar = create :avatar, asset: @asset, owner: @owner
    @reference = create :asset_reference, uploadable: @avatar

    @org_avatar = create :avatar, asset: @asset, uploader: @owner, owner: @org
    @org_reference = create :asset_reference, uploadable: @org_avatar
    @user = create :user, login: "user"

    @cropped_avatar = create :avatar, cropped_x: 1, cropped_y: 2, cropped_width: 3, cropped_height: 4,
      uploader: @user, asset: @asset, owner: @user

    @business = Business.first || create(:business, organizations: [@org], owners: [@owner])
    @business_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @business.id, owner_type: "Business"))

    @team = Team.first || create(:team, organization: @org)
    @team_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @team.id, owner_type: "Team"))

    @oauth_app = OauthApplication.first || create(:oauth_application, user: @owner)
    @oauth_app_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @oauth_app.id, owner_type: "OauthApplication"))

    @integration = Integration.first || create(:integration, :with_active_hook, owner: @owner)
    @integration_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @integration.id, owner_type: "Integration"))

    @listing = create(:marketplace_listing, listable: @oauth_app)
    @listing_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @listing.id, owner_type: "Marketplace::Listing"))

    @repo = create(:repository, owner: @owner)
    @repo_action = create(:repository_action, :listed, repository: @repo)
    @action_avatar = Avatar.upload(@owner, Sham.sha256, @meta.merge(owner_id: @repo_action.id, owner_type: "RepositoryAction"))
  end

  uploadable_tests_for Avatar, policy_path: :avatars,
    policy_attributes: [:size, :content_type, :organization_id, :owner_id, :owner_type]

  # assert that the uploadable asset is consistent
  def assert_asset(avatar, asset)
    assert_equal asset, avatar.asset
    assert_equal [asset], avatar.assets
  end

  # assert that the uploadable has been created properly
  def assert_uploadable(avatar)
    assert_equal @user, avatar.owner
    assert_equal @user, avatar.uploader
  end

  # create an uploadable
  def create_uploadable(oid, meta)
    uploader = meta.delete(:uploader)

    Avatar.upload(uploader || @user, oid, uploadable_attributes(meta))
  end

  def uploadable_attributes(overwrites = {})
    default = {
      content_type: "image/png",
      size: 1,
      cropped_x: 1,
      cropped_y: 2,
      cropped_width: 3,
      cropped_height: 4,
      width: 5,
      height: 6,
      owner_type: "User",
      owner_id: @user.id,
    }
    default.update(overwrites).with_indifferent_access
  end

  context "(Avatar::Shared)" do
    test "internal uri template" do
      @cropped_avatar.alambic_size_filter = 2 # ignored
      url, rawquery = @cropped_avatar.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{@asset.oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "png", query["filter[image.encode]"]
      assert_equal "1,2,3,3", query["filter[image.crop]"]
      assert_equal "image/png", query["type"]
      assert_equal @cropped_avatar.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 5, query.size
    end

    test "internal uri template for original image" do
      @cropped_avatar.alambic_use_original_filter = true
      url, rawquery = @cropped_avatar.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{@asset.oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "png", query["filter[image.encode]"]
      assert_equal "image/png", query["type"]
      assert_equal @cropped_avatar.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 4, query.size
    end

    test "internal uri template without encoding" do
      @cropped_avatar.id = Avatar::Shared::EARLIEST_FILTERED_ID + 1
      url, rawquery = @cropped_avatar.uri_template.split("?", 2)
      query = Rack::Utils.parse_query(rawquery)
      assert_equal "media:/#{GitHub.alambic_path_prefix}/#{@asset.oid}", url
      assert_equal "{size}", query["s"]
      assert_equal "1,2,3,3", query["filter[image.crop]"]
      assert_equal "image/jpeg", query["type"]
      assert_equal @cropped_avatar.updated_at.to_i.to_s, query["last_mod"]
      assert_equal 4, query.size
    end

    test "image filter" do
      assert filter = @cropped_avatar.alambic_image_filter
      assert_equal "1,2,3,3", filter[:params][:crop], filter.inspect
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "image filter for original image" do
      @cropped_avatar.alambic_use_original_filter = true
      assert filter = @cropped_avatar.alambic_image_filter
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:crop], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "image filter with resize" do
      @cropped_avatar.alambic_size_filter = 2
      assert filter = @cropped_avatar.alambic_image_filter
      assert_equal "1,2,3,3", filter[:params][:crop], filter.inspect
      assert_equal :png, filter[:params][:encode], filter.inspect
      assert_equal "2,2", filter[:params][:resize], filter.inspect
    end

    test "image filter without encoding" do
      @cropped_avatar.id = Avatar::Shared::EARLIEST_FILTERED_ID + 1
      assert filter = @cropped_avatar.alambic_image_filter
      assert_equal "1,2,3,3", filter[:params][:crop], filter.inspect
      assert_nil filter[:params][:encode], filter.inspect
      assert_nil filter[:params][:resize], filter.inspect
    end

    test "#encode_to_png?" do
      av = @avatar
      av.id = 1
      assert av.encode_to_png?

      av.id = Avatar::Shared::EARLIEST_FILTERED_ID + 1
      refute av.encode_to_png?
    end

    test "#cropped with dimensions" do
      assert @cropped_avatar.cropped?
      assert_equal "1,2,3,3", @cropped_avatar.cropped_dimensions
    end

    test "builds url" do
      assert_equal "#{GitHub.alambic_assets_url}/avatars/#{@avatar.id}", @avatar.url
    end

    test "surrogate_key for user avatar" do
      assert_equal "avatars/#{@avatar.id}", @avatar.avatar_surrogate_key
    end

    test "surrogate_key for organization avatar" do
      assert_equal "avatars/#{@org_avatar.id}", @org_avatar.avatar_surrogate_key
    end
  end

  ## Avatar tests
  test "allows content types" do
    ctypes = Avatar.allowed_content_types
    assert_includes ctypes, "image/gif"
    assert_includes ctypes, "image/png"
    assert_includes ctypes, "image/jpeg"
  end

  test "can upload own avatar" do
    Avatar.delete_all
    assert_nil Avatar.fetch(@owner, @asset.oid)
    meta = uploadable_attributes(content_type: "image/png", size: 1, owner_id: @owner.id)
    avatar = Avatar.upload(@owner, @asset.oid, meta)
    assert_equal @owner, avatar.owner
    assert_equal @owner, avatar.uploader
    assert_equal avatar, Avatar.fetch(@owner, @asset.oid)
  end

  test "fetch user avatar" do
    assert_equal @avatar, Avatar.fetch(@owner, @avatar.asset.oid)
  end

  test "fetch organization avatar" do
    assert_equal @org_avatar, Avatar.fetch(@org, @org_avatar.asset.oid)
  end

  test "sets all avatar metadata" do
    avatar = create_uploadable Sham.sha256, size: 10
    assert_valid avatar
    assert_equal "image/png", avatar.content_type
    assert_equal 1, avatar.cropped_x
    assert_equal 2, avatar.cropped_y
    assert_equal 3, avatar.cropped_width
    assert_equal 3, avatar.cropped_height
  end

  test "user lists their avatars" do
    meta = uploadable_attributes(size: 42, content_type: "image/png", width: 1, height: 2)
    avatar = Avatar.upload(@user, Sham.sha256, meta)

    assert_equal [avatar, @cropped_avatar], @user.avatars
  end

  test "automatically crops wide image" do
    asset = create :asset, width: 247, height: 234
    avatar = create :avatar, asset: asset, owner: @owner
    assert_equal 234, avatar.cropped_width
    assert_equal 234, avatar.cropped_height
    assert_equal 6, avatar.cropped_x
    assert_equal 0, avatar.cropped_y
  end

  test "automatically crops tall image" do
    asset = create :asset, width: 678, height: 908
    avatar = create :avatar, asset: asset, owner: @owner
    assert_equal 678, avatar.cropped_width
    assert_equal 678, avatar.cropped_height
    assert_equal 0, avatar.cropped_x
    assert_equal 115, avatar.cropped_y
  end

  test "does not crop square image" do
    asset = create :asset, width: 100, height: 100
    avatar = create :avatar, asset: asset, owner: @owner
    assert_equal 0, avatar.cropped_width
    assert_equal 0, avatar.cropped_height
    assert_equal 0, avatar.cropped_x
    assert_equal 0, avatar.cropped_y
  end

  context "with 150x100 asset:" do
    {
      # cropped_x, cropped_y, cropped_width, cropped_height
      [75, 0, 100, 100] => [75, 0, 75, 75],
      [0, 25, 100, 100] => [0, 25, 75, 75],
      [0, 0, 150, 100] => [0, 0, 100, 100],
      [-1, -1, 100, 100] => [0, 0, 100, 100],
      [0, 0, 100, 100] => [0, 0, 100, 100],
    }.each do |initial, expected|
      test("crops with %dx%d (%dw %dh) becomes %dx%d (%dw %dh)" % (initial + expected)) do
        avatar = build :avatar, asset: @cropped_asset, owner: @owner,
          cropped_x: initial[0],
          cropped_y: initial[1],
          cropped_width: initial[2],
          cropped_height: initial[3]
        assert_valid avatar
        assert_equal expected[0], avatar.cropped_x
        assert_equal expected[1], avatar.cropped_y
        assert_equal expected[2], avatar.cropped_width
        assert_equal expected[3], avatar.cropped_height
      end
    end
  end

  context "urls" do
    test "url with query" do
      avatar = build :avatar, asset: @asset, owner: @owner
      query = { s: 10 }
      query = URI.parse(avatar.url(query)).query
      assert_match "s=10", query
      refute_match "token=", query
    end

    test "url with query and actor" do
      avatar = build :avatar, asset: @asset, owner: @owner
      query = { s: 10 }
      query = URI.parse(avatar.url(query, @owner)).query
      assert_match "s=10", query
      assert_match "token=", query
    end

    test "original url" do
      avatar = build :avatar, asset: @asset, owner: @owner
      query = URI.parse(avatar.original_url).query
      assert_match "orig=1", query
      refute_match "token=", query
    end

    test "original url with actor" do
      avatar = build :avatar, asset: @asset, owner: @owner
      query = URI.parse(avatar.original_url(@owner)).query
      assert_match "orig=1", query
      assert_match "token=", query
    end
  end

  test "validates asset presence" do
    avatar = build :avatar, asset: @asset, owner: @owner
    assert_equal false, avatar.valid?
    refute_equal [], avatar.errors["asset_id"]
  end

  test "policy validates for user" do
    meta = uploadable_attributes(content_type: "image/png", size: 1)
    avatar = Avatar.create_for_policy(@user, meta)
    assert !avatar.new_record?, avatar.errors.full_messages.to_sentence
    assert_equal @user, avatar.owner
    assert_equal "image/png", avatar.content_type
    assert_equal 1, avatar.size
    assert_match "/avatars", avatar.storage_policy(actor: @owner).upload_url
  end

  test "policy validates for organization" do
    avatar = Avatar.create_for_policy(@owner, uploadable_attributes(owner_id: @org.id))
    assert !avatar.new_record?, avatar.errors.full_messages.to_sentence
    assert_equal @org, avatar.owner
    assert_equal "image/png", avatar.content_type
    assert_equal 1, avatar.size
    assert_match "/avatars", avatar.storage_policy(actor: @owner).upload_url
  end

  test "policy validates size" do
    meta = uploadable_attributes(content_type: "image/png", size: 10.megabytes)
    avatar = Avatar.create_for_policy(@user, meta)
    assert avatar.new_record?
    assert_equal @user, avatar.owner
    assert_equal "image/png", avatar.content_type
    assert_equal 10.megabytes, avatar.size
  end

  test "policy validates type" do
    meta = uploadable_attributes(content_type: "image/svg", size: 1)
    avatar = Avatar.create_for_policy(@user, meta)
    assert avatar.new_record?
    assert_equal @user, avatar.owner
    assert_equal @user, avatar.uploader
    assert avatar.can_upload?
    assert_equal "image/svg", avatar.content_type
    assert_equal 1, avatar.size
  end

  test "policy validates user ownership" do
    avatar = Avatar.create_for_policy(@user, "content_type" => "image/png", "size" => 1, "organization_id" => @owner.id)
    assert avatar.new_record?
    assert_nil avatar.owner # Organization.find doesn't find users
    assert_equal @user, avatar.uploader
    assert !avatar.can_upload?
    assert_equal "image/png", avatar.content_type
    assert_equal 1, avatar.size
  end

  test "policy validates organization ownership" do
    meta = uploadable_attributes(content_type: "image/png", size: 1, owner_id: @org.id)
    avatar = Avatar.create_for_policy(@user, meta)
    assert avatar.new_record?
    assert_equal @org, avatar.owner
    assert_equal @user, avatar.uploader
    assert !avatar.can_upload?
    assert_equal "image/png", avatar.content_type
    assert_equal 1, avatar.size
  end

  test "asset size validation" do
    asset = create :asset, size: 2.megabytes
    avatar = build :avatar, asset: asset, owner: @owner
    assert_equal false, avatar.valid?
    refute_equal [], avatar.errors["size"]
  end

  test "validates cannot have more than one asset" do
    asset = build :asset
    @avatar.assets << asset
    assert_equal false, @avatar.valid?
    refute_equal [], @avatar.errors["asset_id"]
  end

  test "validates asset id matches the linked asset" do
    @avatar.asset_id = @asset.id + 1
    assert_equal false, @avatar.valid?
    refute_equal [], @avatar.errors["asset_id"]
  end

  test "validates uniqueness of asset_id scoped to owner_id" do
    avatar = build :avatar, owner: @owner, asset: @asset
    assert_equal false, avatar.valid?
    refute_equal [], avatar.errors["asset_id"]
  end

  test "validates owner presence" do
    avatar = build :avatar, asset: @asset, owner: nil
    assert_equal false, avatar.valid?
    refute_equal [], avatar.errors["owner"]
  end

  test "delete avatar" do
    @avatar.destroy
    assert_nil Avatar.find_by_id(@avatar.id)
    assert_equal @asset, Asset.find_by_id(@avatar.asset_id)
  end

  test "delete lone primary avatar" do
    primary = PrimaryAvatar.set @avatar, @owner
    assert_equal primary, PrimaryAvatar.find_by_id(primary.id)

    @avatar.destroy
    assert_nil Avatar.find_by_id(@avatar.id)
    assert_nil PrimaryAvatar.find_by_id(primary.id)
    assert_equal @asset, Asset.find_by_id(@avatar.asset_id)
  end

  test "re-set primary avatar after deleting primary avatar" do
    avatar1 = create_uploadable Sham.sha256, size: 10
    avatar2 = create_uploadable Sham.sha256, size: 10
    primary = PrimaryAvatar.set avatar2, @user

    avatar2.destroy
    assert_nil Avatar.find_by_id(avatar2.id)
    assert Asset.find_by_id(avatar2.asset_id)
    assert primary = PrimaryAvatar.find_by_id(primary.id)
    assert_equal avatar1, primary.avatar
  end

  test "clears the primaray avatar if previous avatar was uploaded by a non-admin" do
    old_member = create(:user)
    @org.add_admin old_member

    old_avatar = create_uploadable Sham.sha256,
      size: 10,
      owner_id: @org.id,
      uploader: old_member
    primary = PrimaryAvatar.set @org_avatar, @owner

    @org.remove_member! old_member

    @org_avatar.destroy
    assert_nil Avatar.find_by_id(@org_avatar.id)
    assert_nil PrimaryAvatar.find_by_id(primary.id)
  end

  test "purges cdn on save" do
    key = "avatars/#{@avatar.id}"
    assert_purged_keys key do
      @avatar.save!
    end
  end

  test "purges cdn on destroy" do
    key = "avatars/#{@avatar.id}"
    assert_purged_keys key do
      @avatar.destroy
    end
  end

  test "purges cdn without cdn config" do
    @avatar.purge_cdn
  end

  test "storage enterprise policy" do
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    policy = @avatar.storage_policy
    assert_kind_of Storage::ClusterPolicy, policy

    expected = "/storage/avatars/#{@avatar.id}"
    assert_match expected, @avatar.reload.url
    assert_match expected, policy.download_link[:href]
  end

  test "storage production policy" do
    GitHub.storage_cluster_enabled = false
    GitHub.s3_uploads_enabled = true
    policy = @avatar.storage_policy
    assert_kind_of Storage::AlambicPolicy, policy
    refute_kind_of Storage::ClusterPolicy, policy

    expected = "/assets/avatars/#{@avatar.id}"
    assert_match expected, @avatar.reload.url
    assert_match expected, policy.download_link[:href]
  end

  test "storage s3 policy" do
    GitHub.storage_cluster_enabled = false
    GitHub.s3_uploads_enabled = true
    @avatar.storage_provider = "s3_production_data"
    policy = @avatar.storage_policy
    assert_kind_of Storage::S3Policy, policy
    refute_kind_of Storage::ClusterPolicy, policy
    refute_kind_of Storage::AlambicPolicy, policy
  end

  context "quarantine" do
    test "instruments a quarantine event" do
      events = subscribe "avatar.quarantine"

      assert @avatar.quarantine(reason: "CSAM")

      expected_payload = {
        user_id: @avatar.owner.id,
        avatar_id: @avatar.id,
        reason: "CSAM",
      }

      assert event = events.pop, "avatar.quarantine event was expected"
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments a quarantine event in the audit log" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        user_id: @avatar.owner.id,
        avatar_id: @avatar.id,
        reason: "CSAM",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for an organization owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @org_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        user_id: @org_avatar.owner.id,
        avatar_id: @org_avatar.id,
        reason: "CSAM",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for a business owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @business_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        business_id: @business_avatar.owner.id,
        avatar_id: @business_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for a team owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @team_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        team_id: @team_avatar.owner.id,
        avatar_id: @team_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for an oauth app owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @oauth_app_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        oauth_application_id: @oauth_app_avatar.owner.id,
        avatar_id: @oauth_app_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for an integration app owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @integration_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        integration_id: @integration_avatar.owner.id,
        avatar_id: @integration_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for a marketplace listing owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @listing_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        marketplace_listing_id: @listing_avatar.owner.id,
        avatar_id: @listing_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments a quarantine event in the audit log for a marketplace action owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.quarantine") do
        @action_avatar.quarantine(reason: "CSAM")
      end

      expected_payload = {
        repository_action_id: @action_avatar.owner.id,
        avatar_id: @action_avatar.id,
        reason: "CSAM"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "unquarantine" do
    test "instruments an unquarantine event" do
      events = subscribe "avatar.unquarantine"

      assert @avatar.unquarantine(reason: "CSAM")

      expected_payload = {
        user_id: @avatar.owner.id,
        avatar_id: @avatar.id,
        reason: "CSAM",
      }

      assert event = events.pop, "avatar.unquarantine event was expected"
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments a unquarantine event in the audit log" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        user_id: @avatar.owner.id,
        avatar_id: @avatar.id,
        reason: "confirmed false positive",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for an organization owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @org_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        user_id: @org_avatar.owner.id,
        avatar_id: @org_avatar.id,
        reason: "confirmed false positive",
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for a business owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @business_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        business_id: @business_avatar.owner.id,
        avatar_id: @business_avatar.id,
        reason: "confirmed false positive"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for a team owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @team_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        team_id: @team_avatar.owner.id,
        avatar_id: @team_avatar.id,
        reason: "confirmed false positive"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for an oauth app owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @oauth_app_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        oauth_application_id: @oauth_app_avatar.owner.id,
        avatar_id: @oauth_app_avatar.id,
        reason: "confirmed false positive"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for an integration app owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @integration_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        integration_id: @integration_avatar.owner.id,
        avatar_id: @integration_avatar.id,
        reason: "confirmed false positive"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "instruments an unquarantine event in the audit log for a marketplace listing owned avatar" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.unquarantine") do
        @listing_avatar.unquarantine(reason: "confirmed false positive")
      end

      expected_payload = {
        marketplace_listing_id: @listing_avatar.owner.id,
        avatar_id: @listing_avatar.id,
        reason: "confirmed false positive"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "destroy" do
    test "instruments a destroy event" do
      events = subscribe "avatar.destroy"

      assert @avatar.destroy

      expected_payload = {
        avatar_id: @avatar.id,
        user: @avatar.owner.login,
        user_id: @avatar.owner.id,
      }

      assert event = events.pop, "avatar.destroy event was expected"
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments a destroy event in the audit log" do
      events = assert_performed_audit_entries(count: 1, only: "avatar.destroy") do
        @avatar.destroy
      end

      expected_payload = {
        avatar_id: @avatar.id,
        user: @avatar.owner.login,
        user_id: @avatar.owner.id,
      }

      assert_subset_hash expected_payload, events.first
    end
  end
end
