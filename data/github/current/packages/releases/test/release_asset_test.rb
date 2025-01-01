# typed: true
# frozen_string_literal: true

require "test_helper"

class NewReleaseAssetTest < GitHub::TestCase
  include UploadableTestHelpers
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @user = create(:user)
    @repo = create :repository, owner: @user, from_example: :repository_test_simple
    @rel = create :release, repository: @repo, author: @user, tag_name: "v1"
    @asset = ReleaseAsset.new uploader: @user, release: @rel
    save_file_for_uploadable @asset, name: "tater.jpg"
  end

  test "requires a valid size" do
    asset = ReleaseAsset.new uploader: @user, release: @rel, size: 0
    refute_predicate asset, :valid?
    asset = ReleaseAsset.new uploader: @user, release: @rel, size: 2.gigabytes + 1
    refute_predicate asset, :valid?
  end

  test "requires valid release_id" do
    asset = ReleaseAsset.new uploader: @user, release: @rel, size: 123
    asset.release_id = Release.maximum(:id) + 100
    refute asset.valid?
    assert_same_elements [:repository_id, :release_id], asset.errors.messages.keys
  end

  test "requires valid label" do
    label = "\u{1F411} sheep emoji \u{1F411}"
    asset = ReleaseAsset.new uploader: @user, release: @rel, size: 123, name: "hello", label: label
    refute asset.valid?
    assert_same_elements [:label], asset.errors.messages.keys
  end

  test "cannot set content_type to application/x-www-form-urlencoded" do
    assert @asset.valid?
    @asset.content_type = "application/x-www-form-urlencoded"
    assert !@asset.valid?, "perfectly fine setting content_type"
    assert @asset.errors[:content_type]
  end

  context "s3 policy" do
    test "can set blank content_type" do
      assert @asset.valid?
      @asset.content_type = nil
      assert @asset.valid?
      assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, @asset.content_type
      assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, @asset.downloadable_content_type
      assert_equal "attachment; filename=#{@asset.name}", @asset.served_content_disposition
      assert_nil @asset.served_content_type

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::S3Policy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "attachment; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "can always download from octet-stream type" do
      ctype = @asset.content_type = "image/jpeg"
      assert_equal ctype, @asset.content_type
      assert_equal ctype, @asset.downloadable_content_type
      assert_nil @asset.served_content_type
      assert_equal "attachment; filename=#{@asset.name}", @asset.served_content_disposition

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::S3Policy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "attachment; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "asset with xpi extension" do
      ctype = @asset.content_type = "image/jpeg"
      @asset[:name] = "whatever.xpi"
      assert_equal "image/jpeg", @asset.content_type
      assert_equal "application/x-xpinstall", @asset.downloadable_content_type
      assert_equal "application/x-xpinstall", @asset.served_content_type

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::S3Policy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "inline; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal "application/x-xpinstall", q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "storage production policy with production_data storage provider" do
      GitHub.s3_uploads_enabled = true
      policy = @asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = "/%d/%s" % [@asset.repository_id, @asset.guid]
      assert_match expected, @asset.reload.url
      dl_link = policy.download_link[:href]
      assert_match expected, dl_link
    end

    test "storage production policy with legacy storage provider" do
      GitHub.s3_uploads_enabled = true
      policy = @asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      @asset.update!(storage_provider: nil)
      @asset.reload

      expected = "/releases/%d/%s%s" % [@asset.repository_id, @asset.guid, File.extname(@asset.name)]
      assert_match expected, @asset.reload.url
      dl_link = policy.download_link[:href]
      assert_match expected, dl_link
    end
  end

  context "Memory Alpha policy" do
    test "can set blank content_type" do
      assert @asset.valid?
      @asset.content_type = nil
      assert @asset.valid?
      assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, @asset.content_type
      assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, @asset.downloadable_content_type
      assert_equal "attachment; filename=#{@asset.name}", @asset.served_content_disposition
      assert_nil @asset.served_content_type

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::MemoryAlphaPolicy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "attachment; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "can always download from octet-stream type" do
      ctype = @asset.content_type = "image/jpeg"
      assert_equal ctype, @asset.content_type
      assert_equal ctype, @asset.downloadable_content_type
      assert_nil @asset.served_content_type
      assert_equal "attachment; filename=#{@asset.name}", @asset.served_content_disposition

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::MemoryAlphaPolicy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "attachment; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal ReleaseAsset::DOWNLOAD_CONTENT_TYPE, q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "asset with xpi extension" do
      ctype = @asset.content_type = "image/jpeg"
      @asset[:name] = "whatever.xpi"
      assert_equal "image/jpeg", @asset.content_type
      assert_equal "application/x-xpinstall", @asset.downloadable_content_type
      assert_equal "application/x-xpinstall", @asset.served_content_type

      if GitHub.s3_uploads_enabled?
        s3_policy = Storage::MemoryAlphaPolicy.new(@asset)
        q = Rack::Utils.parse_query(URI.parse(s3_policy.download_url).query)
        assert_equal "inline; filename=#{@asset.name}", q["response-content-disposition"]
        assert_equal "application/x-xpinstall", q["response-content-type"]
      else
        skip "s3 uploads disabled."
      end
    end

    test "storage production policy with production_data storage provider" do
      GitHub.s3_uploads_enabled = true
      policy = @asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      expected = "/%d/%s" % [@asset.repository_id, @asset.guid]
      assert_match expected, @asset.reload.url
      dl_link = policy.download_link[:href]
      assert_match expected, dl_link
    end

    test "storage production policy with legacy storage provider" do
      GitHub.s3_uploads_enabled = true
      policy = @asset.storage_policy
      assert_kind_of Storage::S3Policy, policy
      assert_equal "private", policy.acl

      @asset.update!(storage_provider: nil)
      @asset.reload

      expected = "/releases/%d/%s%s" % [@asset.repository_id, @asset.guid, File.extname(@asset.name)]
      assert_match expected, @asset.reload.url
      dl_link = policy.download_link[:href]
      assert_match expected, dl_link
    end
  end

  test "gets only uploaded assets" do
    ReleaseAsset.update_all(state: ReleaseAsset.states[:uploaded])
    assert_equal [@asset], Release.find(@rel.id).uploaded_assets

    ReleaseAsset.update_all(state: ReleaseAsset.states[:starter])
    assert_equal [], Release.find(@rel.id).uploaded_assets

    ReleaseAsset.update_all(state: ReleaseAsset.states[:deleted])
    assert_equal [], Release.find(@rel.id).uploaded_assets
  end

  test "rejects .app file" do
    asset = ReleaseAsset.new uploader: @user, release: @rel
    asset.name = "tater.app"
    assert !asset.valid?
    assert asset.errors[:name].present?
  end

  test "sanitizes file name" do
    assert_name_sanitization ReleaseAsset
  end

  test "appends old extension to renamed file name" do
    assert_equal "tater.jpg", @asset.name
    @asset.name = "foo"
    assert_equal "foo.jpg", @asset.name
  end

  test "uses filename as default display name" do
    assert_equal "tater.jpg", @asset.display_name
  end

  test "label overrides filename as display name" do
    @asset.label = "tater"
    assert_equal "tater", @asset.display_name
  end

  test "tracks downloads" do
    assert_equal 0, @asset.downloads
    perform_enqueued_jobs(only: [SlottedCounterIncrementAggregatedJob]) { @asset.download }
    assert_equal 1, @asset.downloads
    assert_equal 1, ReleaseAsset.find(@asset.id).downloads
  end

  test "tracks downloads without memoizing slotted counter" do
    perform_enqueued_jobs(only: [SlottedCounterIncrementAggregatedJob]) { @asset.download }
    assert_equal 1, @asset.downloads
    assert_equal 1, ReleaseAsset.find(@asset.id).downloads
  end

  test "downloads are instrumented" do
    events = subscribe "release_assets.download"
    @asset.download
    assert_equal 1, events.size
    assert event = events.first
    assert_equal @asset.size, event.payload[:size]
  end

  test "pulls content type from upload" do
    assert_equal "image/jpeg", @asset.content_type
  end

  test "pulls size from upload" do
    assert_equal 1.kilobyte, @asset.size
  end

  test "pulls filename from upload" do
    assert_equal "tater.jpg", @asset.name
  end

  test "builds s3 key" do
    GitHub.storage_cluster_enabled = false
    GitHub.s3_uploads_enabled = true

    assert_equal "#{@repo.id}/#{@asset.guid}", @asset.storage_s3_key(@asset.storage_policy)
  end

  test "sets s3 access" do
    assert_equal :private, @asset.storage_s3_access

    asset = ReleaseAsset.find @asset.id
    T.must(asset.repository).public = false

    assert_equal :private, asset.storage_s3_access
  end

  test "storage enterprise policy" do
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    policy = @asset.storage_policy
    assert_kind_of Storage::ClusterPolicy, policy

    ext = UserAsset.asset_extension(@asset)
    assert_match %r{/storage/releases/#{@rel.id}/files/#{@asset.id}}, @asset.reload.url
    assert_match %r{/storage/releases/#{@rel.id}/files/#{@asset.id}}, policy.download_link[:href]
  end

  test "policy model exists" do
    assert pm = ::Storage.policy_creator.for(:releases)
    assert_equal ReleaseAsset, pm.model
  end

  test "gets file url for cluster" do
    GitHub.storage_cluster_enabled = true
    assert_match "/storage/releases/#{@rel.id}/files/#{@asset.id}", @asset.url
  end

  context "#direct_external_storage_url" do
    test "raises when an invalid request method is specified" do
      assert_raises(ArgumentError) { @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "FOO") }
    end

    context "with an S3 backend policy" do
      test "calls metadata_url on HEAD requests (S3Policy)" do
        GitHub.s3_uploads_enabled = true
        Storage::S3Policy.any_instance.expects(:metadata_url).once
        Storage::S3Policy.any_instance.expects(:download_url).never

        @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "HEAD")
      end

      test "calls download_url on GET requests (S3Policy)" do
        GitHub.s3_uploads_enabled = true
        Storage::S3Policy.any_instance.expects(:metadata_url).never
        Storage::S3Policy.any_instance.expects(:download_url).once

        @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "GET")
      end

      test "calls metadata_url on HEAD requests (MemoryAlpha)" do
        GitHub.s3_uploads_enabled = true
        Storage::MemoryAlphaPolicy.any_instance.expects(:metadata_url).once
        Storage::MemoryAlphaPolicy.any_instance.expects(:download_url).never

        @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "HEAD")
      end

      test "calls download_url on GET requests (MemoryAlpha)" do
        GitHub.s3_uploads_enabled = true
        Storage::MemoryAlphaPolicy.any_instance.expects(:metadata_url).never
        Storage::MemoryAlphaPolicy.any_instance.expects(:download_url).once

        @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "GET")
      end

      test "returns metadata_url on HEAD requests" do
        GitHub.s3_uploads_enabled = true

        url = @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "HEAD")
        assert_match %r{https://#{@asset.memory_alpha_fastly_acceleration_bucket(@user, @repo)}/}, url
      end

      test "returns metadata_url on GET requests" do
        GitHub.s3_uploads_enabled = true

        url = @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "GET")
        assert_match %r{https://#{@asset.memory_alpha_fastly_acceleration_bucket(@user, @repo)}/}, url
      end
    end

    test "calls download_url for non-S3 backends on HEAD requests" do
      GitHub.s3_uploads_enabled = false
      GitHub.storage_cluster_enabled = true

      url = @asset.direct_external_storage_url(current_user: @user, current_repository: @repo, request_method: "HEAD")
      assert_equal @asset.url, url
    end

  end

  test "gets file url for s3 with production_data storage provider" do
    # needed so ReleaseAsset#storage_s3_key uses #alambic_s3_content_path_builder
    GitHub.s3_uploads_enabled = true
    assert_match(%r{https://#{@asset.memory_alpha_fastly_acceleration_bucket(@user, @repo)}/}, @asset.url)
  end

  test "gets file url for s3 with legacy storage provider" do
    # needed so ReleaseAsset#storage_s3_key uses #alambic_s3_content_path_builder
    GitHub.s3_uploads_enabled = true
    @asset.update!(storage_provider: nil)
    @asset.reload
    assert_match(%r{https://#{@asset.memory_alpha_fastly_acceleration_bucket(@user, @repo)}/}, @asset.url)
  end

  test "stores in alambic during create" do
    asset = ReleaseAsset.new(uploader: @user, release: @rel)
    assert_predicate asset, :starter?

    save_file_for_uploadable asset

    assert_predicate asset, :uploaded?
  end

  test "builds permalink" do
    asset = ReleaseAsset.new release: @rel, repository: @rel.repository

    # stub these to ensure we're CGI escaping, even though the properties are
    # sanitized and validated by the model

    asset.stub :name, "foo&bar?1.zip" do
      asset.stub :tag_name, "foo%bar/baz" do
        assert_match %r{/releases/download/foo%25bar/baz/foo%26bar%3F1.zip\Z}, asset.permalink
      end
    end
  end

  test "asset with duplicate filename fails validation" do
    assert_nil @asset.replaced_asset

    duplicate = ReleaseAsset.new(name: @asset.name.upcase, uploader: @user, release: @rel,
                                 size: 1, content_type: "image/jpeg")

    refute duplicate.valid?
    assert_equal ["has already been taken"], duplicate.errors[:name]
  end

  test "asset with duplicate filename can be optionally replaced" do
    original = ReleaseAsset.create!(name: "original", uploader: @user, release: @rel,
                                    size: 1, content_type: "image/jpeg")

    duplicate = ReleaseAsset.new(name: original.name, uploader: @user, release: @rel,
                                 size: 1, content_type: "image/jpeg",
                                 deletion_candidates: "0,#{original.id}")

    duplicate.save!
    refute ReleaseAsset.exists?(original.id)
    assert_equal original.id, duplicate.replaced_asset
  end

  test "asset in starter state can be replaced" do
    original = ReleaseAsset.create!(name: "original", uploader: @user, release: @rel,
                                    size: 1, content_type: "image/jpeg", state: :starter)

    duplicate = ReleaseAsset.new(name: original.name, uploader: @user, release: @rel,
                                 size: 1, content_type: "image/jpeg")

    duplicate.save!
    refute ReleaseAsset.exists?(original.id)
    assert_equal original.id, duplicate.replaced_asset
  end

  test "builds storage_cluster_download_token for published release in public repository" do
    @asset.repository.public = true
    @asset.release.state = 0
    assert_nil @asset.storage_cluster_download_token(@asset.storage_policy(actor: @user))
  end

  test "builds storage_cluster_download_token for draft release in public repository" do
    @asset.repository.public = true
    @asset.release.state = 1
    refute_nil @asset.storage_cluster_download_token(@asset.storage_policy(actor: @user))

    assert_raises ArgumentError do
      @asset.storage_cluster_download_token(@asset.storage_policy)
    end
  end

  test "builds storage_cluster_download_token for published release in private repository" do
    @asset.repository.public = false
    @asset.release.state = 0
    refute_nil @asset.storage_cluster_download_token(@asset.storage_policy(actor: @user))

    assert_raises ArgumentError do
      @asset.storage_cluster_download_token(@asset.storage_policy)
    end
  end

  test "builds storage_cluster_download_token for draft release in private repository" do
    @asset.repository.public = false
    @asset.release.state = 1
    refute_nil @asset.storage_cluster_download_token(@asset.storage_policy(actor: @user))

    assert_raises ArgumentError do
      @asset.storage_cluster_download_token(@asset.storage_policy)
    end
  end

  test "can be created by an installation that can write to the repo contents" do
    integration = create(:integration, default_permissions: { "contents" => :write })
    installation = make_integration_installation(integration: integration, repository: @repo)

    asset = ReleaseAsset.new uploader: installation.bot, release: @rel, size: 123

    assert asset.valid?
    assert !asset.errors[:uploader_id].present?
  end

  test "cannot be created by an installation without write access to the repo contents" do
    integration = create(:integration, default_permissions: { "issues" => :write })
    installation = make_integration_installation(integration: integration, repository: @repo)

    asset = ReleaseAsset.new uploader: installation.bot, release: @rel, size: 123

    assert !asset.valid?
    assert asset.errors[:uploader_id].present?
  end

  test "storage_provider" do
    f = ReleaseAsset.new

    GitHub.stubs(:release_asset_azure_storage_account).returns("access")
    GitHub.stubs(:release_asset_azure_storage_access_key).returns("secret")

    f.storage_provider = nil
    assert_equal ReleaseAsset.storage_s3_bucket, f.storage_s3_bucket
    assert_equal GitHub.s3_environment_config[:access_key_id], f.storage_s3_access_key
    assert_equal GitHub.s3_environment_config[:secret_access_key], f.storage_s3_secret_key
    refute_equal "access", f.storage_s3_access_key
    refute_equal "secret", f.storage_s3_secret_key

    f.storage_provider = "s3_production_data"
    assert_equal ReleaseAsset.storage_s3_new_bucket, f.storage_s3_bucket
    assert_equal "access", f.storage_s3_access_key
    assert_equal "secret", f.storage_s3_secret_key
  end

  test "preserves plus in filename" do
    filename = "this+has+plusses.jpg"
    asset = ReleaseAsset.new uploader: @user, release: @rel
    save_file_for_uploadable asset, name: filename
    assert_match asset.name, filename
  end

  test "preserves at sign in filename" do
    filename = "this@has@at@signs.jpg"
    asset = ReleaseAsset.new uploader: @user, release: @rel
    save_file_for_uploadable asset, name: filename
    assert_match asset.name, filename
  end

  test "updates release updated_at timestamp when asset is uploaded" do
    asset = ReleaseAsset.new uploader: @user, release: @rel
    time_before_asset_upload = @rel.updated_at

    Timecop.freeze(3.hours.from_now) do
      save_file_for_uploadable asset, name: "asset.txt"
    end

    assert_operator time_before_asset_upload, "<", @rel.updated_at
  end

  test "updates release updated_at timestamp when existing asset is updated" do
    asset = ReleaseAsset.new uploader: @user, release: @rel
    save_file_for_uploadable asset, name: "asset.txt"

    # test updating the name
    time_before_asset_update = @rel.updated_at

    Timecop.freeze(3.hours.from_now) do
      asset.name = "new_asset.txt"
      asset.save!
    end

    assert_operator time_before_asset_update, "<", @rel.updated_at

    # test updating the label
    time_before_asset_update = @rel.updated_at

    Timecop.freeze(6.hours.from_now) do
      asset.label = "new_myasset.txt"
      asset.save!
    end

    assert_operator time_before_asset_update, "<", @rel.updated_at
  end

  test "updates release updated_at timestamp when asset is destroyed" do
    asset = ReleaseAsset.new uploader: @user, release: @rel
    save_file_for_uploadable asset, name: "asset.txt"
    time_before_asset_destroy = @rel.updated_at

    Timecop.freeze(3.hours.from_now) do
      asset.destroy!
    end

    assert_operator time_before_asset_destroy, "<", @rel.updated_at
  end

  test "doesn't update release updated_at timestamp when release asset creation fails" do
    asset = ReleaseAsset.new uploader: @user, release: @rel
    time_before_asset_upload = @rel.updated_at

    assert_raises ActiveRecord::RecordInvalid do
      Timecop.freeze(3.hours.from_now) do
        # this fails since an asset with the same name was already created in the fixtures
        save_file_for_uploadable asset, name: "tater.jpg"
      end
    end

    assert_equal time_before_asset_upload, @rel.updated_at
  end

  context "global id migration" do
    test "it has a new global id" do
      assert_equal encode_global_id("RA", [0, @repo.id, @asset.id]), @asset.next_global_id
    end

    test "it applies a new global id for objects created after the ready date" do
      asset_before = create_asset(DateTime.parse(Platform::Helpers::GlobalId::COHORT_2) - 1)
      asset_after = create_asset(DateTime.parse(Platform::Helpers::GlobalId::COHORT_2) + 1)

      Platform::Objects::Base::Node.skipping_new_global_id_flag do
        old_id = asset_before.global_relay_id
        new_id = GitHub.enterprise? ? asset_after.global_relay_id : asset_after.next_global_id

        query = <<-'GRAPHQL'
          query ($id: ID!) {
            node(id: $id) {
              ... on Release {
                releaseAssets(last: 2) {
                  nodes {
                    id
                  }
                }
              }
            }
          }
        GRAPHQL

        data = execute_query(
          query,
          viewer: @user,
          "$id": @rel.global_relay_id
        ).data["node"]["releaseAssets"]["nodes"]

        ids = data.map { |node| node["id"] }

        assert_equal old_id, ids[0]
        refute old_id.starts_with?("RA_")

        assert_equal new_id, ids[1]
        assert new_id.starts_with?("RA_") unless GitHub.enterprise?
      end
    end
  end

  private

  def create_asset(datetime)
    asset = ReleaseAsset.new(uploader: @user, release: @rel)
    save_file_for_uploadable(asset, name: "asset-#{datetime}.jpg")
    asset.created_at = datetime
    asset.save!
    asset
  end
end
