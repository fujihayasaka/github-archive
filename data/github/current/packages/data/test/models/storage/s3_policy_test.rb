# typed: false
# frozen_string_literal: true

require "test_helper"

class StorageS3PolicyTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @owner     = create :user, login: "jessicard", password: GitHub.default_password, plan: "large"
    @org       = create :organization, login: "some-org", admin: @owner
    @migration = create :migration, owner: @org, creator: @owner, state: :ready
    @repo      = create :repository, owner: @owner
    @key       = create :public_key, repository: @repo
  end

  setup do
    GitHub.s3_uploads_enabled = nil
    GitHub.stubs(:s3_production_data_access_key).returns("s3_production_data_access_key")
  end

  teardown do
    Storage::Policy.faraday = nil
  end

  def save_repository_file_for(repo, size: 1.megabyte)
    save_file_for_uploadable(
      RepositoryFile.new(uploader: repo.owner, repository: repo),
      name: "test.pdf",
      size: size,
      content_type: "application/pdf",
    )
  end

  test "empty storage provider" do
    repo = create(:repository)
    file = save_repository_file_for(repo)
    assert_equal :s3_production_data, file.storage_provider
  end

  test "set storage provider" do
    RepositoryFile.stubs(:choose_storage_provider) { self.storage_provider = :default }
    file = RepositoryFile.new
    assert_equal :default, file.storage_provider
    file.storage_provider = "s3_production_data"
    assert_equal :s3_production_data, file.storage_provider
  end

  test "stats for download" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    blob = create :media_blob, state: 3
    Storage::S3Policy.new(blob).download_url

    assert stat = stats.timings("storage_policy.url").last
    assert_includes stat.tags, "policy:s3"
    assert_includes stat.tags, "model:media/blob"
    assert_includes stat.tags, "op:download"
  end

  test "stats for upload" do
    blob = create :user_asset, state: 1

    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    Storage::S3Policy.new(blob).policy_hash

    assert stat = stats.timings("storage_policy.url").last
    assert_includes stat.tags, "policy:s3"
    assert_includes stat.tags, "model:user_asset"
    assert_includes stat.tags, "op:upload"
  end

  test "private download url" do
    blob = create :media_blob, state: 3
    url = Storage::S3Policy.new(blob).download_url
    assert_s3_presigned_lfs_url(url)
  end

  test "private download url with defined billing params including deploy key" do
    blob = create :media_blob, state: 3
    url = Storage::S3Policy.new(blob, actor: @owner, repository: @repo, key: @key).download_url
    assert_s3_presigned_lfs_url(url, actor_id: @owner.id, repo_id: @repo.id, key_id: @key.id)
  end

  test "public download url" do
    asset = create :user_asset, state: 1
    url = Storage::S3Policy.new(asset).download_url
    assert_s3_presigned_url(url)
  end

  test "private download link" do
    blob = create :media_blob, state: 3
    link = Storage::S3Policy.new(blob).download_link
    assert_s3_signed_lfs_link(link, presigned: true)
  end

  test "private download link with defined billing params including deploy key" do
    blob = create :media_blob, state: 3
    link = Storage::S3Policy.new(blob, actor: @owner, repository: @repo, key: @key).download_link
    assert_s3_signed_lfs_link(link, presigned: true, actor_id: @owner.id, repo_id: @repo.id, key_id: @key.id)
  end

  test "LFS upload link" do
    asset = create :media_blob, state: 3
    link = Storage::S3Policy.new(asset).lfs_upload_link
    assert_s3_signed_lfs_link(link)
  end

  test "LFS upload link with defined billing params including deploy key" do
    asset = create :media_blob, state: 3
    link = Storage::S3Policy.new(asset, actor: @owner, repository: @repo, key: @key).lfs_upload_link
    assert_s3_signed_lfs_link(link, actor_id: @owner.id, repo_id: @repo.id, key_id: @key.id)

  end

  context "multi-part uploads" do
    context "dotcom importer" do
      test "start upload url" do
        migration_file = create_migration_file(@migration)
        migration_file.supports_multi_part_upload = true
        url_header = Storage::S3Policy.new(migration_file).multi_part_upload_url_headers(migration_file.state)
        url = url_header[:url]
        headers = url_header[:headers]
        parsed_url = URI(url)

        assert_equal "/migration/#{@migration.id}/#{migration_file.id}?uploads=", "#{parsed_url.path}?#{parsed_url.query}"
        assert headers["Authorization"], "Should have authorization header"
      end

      test "upload part url" do
        migration_file = create_migration_file(@migration)
        migration_file.state = :multipart_upload_started
        migration_file.supports_multi_part_upload = true
        migration_file.part_number = 2
        migration_file.part_sha = "PART_SHA_256"
        migration_file.multi_part_upload_id = "S3_Upload_ID"
        url_header = Storage::S3Policy.new(migration_file).multi_part_upload_url_headers(migration_file.state)
        url = url_header[:url]
        headers = url_header[:headers]
        parsed_url = URI(url)

        assert_equal "/migration/#{@migration.id}/#{migration_file.id}?partNumber=2&uploadId=S3_Upload_ID", "#{parsed_url.path}?#{parsed_url.query}"
        assert headers["Authorization"], "Should have authorization header"
        assert_equal "PART_SHA_256", headers["x-amz-content-sha256"]
      end

      test "list parts url" do
        migration_file = create_migration_file(@migration)
        migration_file.state = :multipart_upload_list_parts
        migration_file.supports_multi_part_upload = true
        migration_file.multi_part_upload_id = "S3_Upload_ID"
        url_header = Storage::S3Policy.new(migration_file).multi_part_upload_url_headers(migration_file.state)
        url = url_header[:url]
        headers = url_header[:headers]
        parsed_url = URI(url)

        assert_equal "/migration/#{@migration.id}/#{migration_file.id}?uploadId=S3_Upload_ID", "#{parsed_url.path}?#{parsed_url.query}"
        assert headers["Authorization"], "Should have authorization header"
      end

      test "complete upload url" do
        migration_file = create_migration_file(@migration)
        migration_file.state = :multipart_upload_completed
        migration_file.supports_multi_part_upload = true
        migration_file.multi_part_upload_id = "S3_Upload_ID"
        migration_file.part_sha = "BODY_SHA_256"
        url_header = Storage::S3Policy.new(migration_file).multi_part_upload_url_headers(migration_file.state)
        url = url_header[:url]
        headers = url_header[:headers]
        parsed_url = URI(url)

        assert_equal "/migration/#{@migration.id}/#{migration_file.id}?uploadId=S3_Upload_ID", "#{parsed_url.path}?#{parsed_url.query}"
        assert headers["Authorization"], "Should have authorization header"
        assert_equal "BODY_SHA_256", headers["x-amz-content-sha256"]
      end
    end
  end

  test "successfully uploads s3 object" do
    file = create :user_asset

    s3_upload_with(file: file) do
      res = file.storage_policy.upload_contents(StringIO.new("TEST"))
      assert_equal 204, res.status
    end
  end

  test "raises HttpError when S3 upload fails with status 500" do
    repo = create(:public_repository, owner: @org)
    file = create :user_asset, user_id: @owner.id, repository_id: repo.id

    s3_upload_with(file: file, status: 500) do
      assert_raises Storage::Policy::HttpError do
        file.storage_policy.upload_contents!(StringIO.new("TEST"))
      end
    end
  end

  test "delete s3 object" do
    file = create :marketplace_listing_screenshot
    path = "/#{file.marketplace_listing_id}/#{file.guid}"
    assert_storage_policy_delete(file, path) do
      res = file.storage_delete_object
      assert_equal 200, res.status
    end
  end

  test "delete missing s3 object" do
    file = create :marketplace_listing_screenshot
    path = "/#{file.marketplace_listing_id}/#{file.guid}"
    assert_storage_policy_delete(file, path, delete_status: 404) do
      res = file.storage_delete_object
      assert_equal 404, res.status
    end

    # 404 deletion on uploaded file raises exception
    file.state = :uploaded

    assert_storage_policy_delete(file, path, delete_status: 404) do
      assert_raises Storage::Uploadable::DeletionError do
        file.storage_delete_object
      end
    end
  end

  test "attempt delete s3 object" do
    file = create :marketplace_listing_screenshot
    path = "/#{file.marketplace_listing_id}/#{file.guid}"
    assert_storage_policy_delete(file, path, delete_status: 500) do
      assert_raises Storage::Uploadable::DeletionError do
        file.storage_delete_object
      end
    end
  end

  def create_package_file(repo)
    registry_package = repo.packages.build(name: "test-docker-image", package_type: Registry::Package.symbolize_package_type(:docker))
    package_version1 = registry_package.package_versions.build(version: "1.0.0", author: repo.owner, sha256: "1.0.0 sha256", size: 2067)
    assert registry_package.save!

    package_file = Registry::File.storage_new(nil, nil, {
      repository: repo,
      registry_package_name: "express",
      registry_package_type: "docker",
      })
    package_file.package_version = package_version1
    package_file.guid = "THIS_IS_THE_FILE_GUID"
    package_file
  end

  def create_migration_file(migration)
    migration_file = migration.build_file(uploader: migration.creator)
    save_file_for_uploadable migration_file, use_multi_part: true, name: "migration_archive.tar.gz", size: 20, content_type: "application/x-gzip", guid: "migration_file_guid"
    migration_file
  end

  def s3_upload_with(file:, status: 204, &block)
    bucket = UserAsset.storage_s3_new_bucket
    key = "#{file.user_id}/#{file.id}-#{file.guid}#{File.extname(file.name)}"
    access_key = GitHub.s3_production_data_access_key

    assert_storage_policy_s3_upload(
      bucket: bucket,
      key: key,
      access_key: access_key,
      acl: "private",
      content: "TEST",
      content_type: file.content_type,
      status: status,
      &block
    )
  end
end
