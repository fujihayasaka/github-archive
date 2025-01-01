# typed: true
# frozen_string_literal: true

require "test_helper"

class UploadManifestFileTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @collaborator = create(:user)
    @rando = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :simple)
    @repo.add_member(@collaborator)
    @manifest = UploadManifest.create(repository: @repo, uploader: @owner)

  end

  setup do
    @file = @manifest.files.build(
      repository: @repo,
      uploader: @owner,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)
  end

  test "requires repository, uploader, and manifest" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    refute subject.new_record?
    assert subject.valid?
  end

  test "assigns a default content type" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      content_type: "",
      size: 42)

    refute subject.new_record?
    assert subject.valid?
    assert_equal "application/octet-stream", subject.content_type
  end

  test "does not overwrite a provided content type with the default" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    refute subject.new_record?
    assert subject.valid?
    assert_equal "text/plain", subject.content_type
  end

  test "prevents huge directory names" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      directory: "a" * 1025,
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:directory].empty?
  end

  test "prevents huge unicode directory names" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      directory: "\u043B" * 1000,
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:directory].empty?
  end

  test "prevents large file uploads" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 100.megabytes)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:size].empty?
  end

  test "prevents excessive number of file uploads" do
    max_files = 3

    max_files.times do
      subject = UploadManifestFile.create(
        repository: @repo,
        uploader: @owner,
        manifest: @manifest,
        name: "test.txt",
        content_type: "text/plain",
        size: 42)
      assert subject.valid?
    end

    subject = UploadManifestFile.new(
      repository: @repo,
      uploader: @owner,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)
    subject.max_files_per_manifest = max_files
    subject.save

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:file_count].empty?
  end

  test "uploader must match manifest creator" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @collaborator,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:uploader].empty?
  end

  test "uploader must have push access to repository" do
    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @rando,
      manifest: @manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:uploader].empty?
  end

  test "prevents uploads to processing manifests" do
    manifest = UploadManifest.create(
      repository: @repo,
      uploader: @owner,
      state: :uploaded)

    subject = UploadManifestFile.create(
      repository: @repo,
      uploader: @owner,
      manifest: manifest,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:manifest].empty?
  end

  test "rejects directory navigation characters" do
    @file.directory = "/../../../"
    refute @file.valid?
    refute @file.errors[:directory].empty?
  end

  test "removes extra directory separators" do
    subject = UploadManifestFile.new(
      manifest: @manifest,
      repository: @repo,
      directory: "/a/b//c/")
    assert_equal "a/b/c", subject.directory
  end

  test "allow empty files" do
    empty_file = @manifest.files.build(
      repository: @repo,
      uploader: @owner,
      name: "empty_file.txt",
      content_type: "text/plain",
      size: 0)

    assert empty_file.valid?
  end

  context "creating the full path name" do
    test "bare file name without directory" do
      subject = UploadManifestFile.new(
        manifest: @manifest,
        repository: @repo,
        directory: "",
        name: "test.txt")
      assert_equal "test.txt", subject.full_name
    end

    test "bare file name with nil directory" do
      subject = UploadManifestFile.new(
        manifest: @manifest,
        repository: @repo,
        directory: nil,
        name: "test.txt")
      assert_equal "test.txt", subject.full_name
    end

    test "concatenated directory without trailing separator" do
      subject = UploadManifestFile.new(
        manifest: @manifest,
        repository: @repo,
        directory: "a/b/c",
        name: "test.txt")
      assert_equal "a/b/c/test.txt", subject.full_name
    end

    test "concatenated directory with trailing separator" do
      subject = UploadManifestFile.new(
        manifest: @manifest,
        repository: @repo,
        directory: "a/b/c/",
        name: "test.txt")
      assert_equal "a/b/c/test.txt", subject.full_name
    end

    test "uses manifest directory as base" do
      manifest = UploadManifest.new(directory: "base/one/two")
      subject = UploadManifestFile.new(
        manifest: manifest,
        repository: @repo,
        directory: "a/b/c/",
        name: "test.txt")
      assert_equal "base/one/two/a/b/c/test.txt", subject.full_name
    end

    test "does not allow non-printable characters" do
      subject = UploadManifestFile.new(
        manifest: @manifest,
        repository: @repo,
        name: "\0.txt")
      refute subject.valid?
      refute subject.errors[:name].empty?
    end
  end

  context "storing file contents as a git blob" do
    test "saves a blob on a 200 response" do

      subject = UploadManifestFile.create(
        repository: @repo,
        uploader: @owner,
        manifest: @manifest,
        name: "test.txt",
        content_type: "text/plain",
        size: 3)

      stub_request(:get, %r{/#{@repo.id}/#{subject.id}}).to_return(body: "abc")

      sha = @repo.spokes_api.resolve_object(object_name: "refs/heads/master")

      assert_nil subject.blob_oid, "file should not have oid"
      oid = subject.to_blob
      refute_nil subject.blob_oid, "blob oid not saved"
      assert_equal subject.blob_oid, oid

      assert_equal sha, @repo.spokes_api.resolve_object(object_name: "refs/heads/master"), "ref sha changed"

      blobs = @repo.rpc.read_blobs([subject.blob_oid])
      assert_equal "abc", blobs.first["data"], "blob data saved incorrectly"
    end

    test "does not save a blob on a 404 response" do
      subject = UploadManifestFile.create(
        repository: @repo,
        uploader: @owner,
        manifest: @manifest,
        name: "test.txt",
        content_type: "text/plain",
        size: 3)

      stub_request(:get, %r{/#{@repo.id}/#{subject.id}}).to_return(status: 404)

      assert_raises(RuntimeError) do
        subject.to_blob
      end
      assert_nil subject.blob_oid
    end
  end
end

class UploadManifestFileInS3Test < GitHub::TestCase
  fixtures do
    @manifest = create(:upload_manifest)
    @default_file = create(:upload_manifest_file, manifest: @manifest, storage_provider: "default")
    @prod_file = create(:upload_manifest_file, manifest: @manifest, storage_provider: "s3_production_data")
  end

  setup do
    GitHub.stubs(:s3_production_data_access_key).returns("s3_production_data_access_key")
    GitHub.stubs(:s3_production_data_secret_key).returns("s3_production_data_secret_key")
    GitHub.stubs(:s3_environment_config).returns(
      asset_bucket_name: "legacy-bucket-name",
      access_key_id: "legacy-access-key",
      secret_access_key: "legacy-secret-key",
    )
  end

  test "bucket" do
    assert_equal "github-test-upload-manifest-file-7fdce7", @default_file.storage_s3_bucket
    assert_equal "github-test-upload-manifest-file-7fdce7", @prod_file.storage_s3_bucket
  end

  test "key" do
    assert_equal "#{@manifest.repository_id}/#{@default_file.id}", @default_file.storage_s3_key(nil)
    assert_equal "#{@manifest.repository_id}/#{@prod_file.id}", @prod_file.storage_s3_key(nil)
  end

  test "access key" do
    assert_equal "s3_production_data_access_key", @default_file.storage_s3_access_key
    assert_equal "s3_production_data_access_key", @prod_file.storage_s3_access_key
  end

  test "secret key" do
    assert_equal "s3_production_data_secret_key", @default_file.storage_s3_secret_key
    assert_equal "s3_production_data_secret_key", @prod_file.storage_s3_secret_key
  end
end

class UploadManifestFileWithStorageClusterEnabledTest < GitHub::TestCase
  setup do
    GitHub.storage_cluster_enabled = true
  end

  teardown do
    GitHub.storage_cluster_enabled = false
  end

  test "should clear out the storage_blob_id and create a Storage::Purge object" do
    blob = create :storage_blob
    subject = create(:upload_manifest_file,
      size: blob.size,
      storage_blob: blob,
    )
    GitHub::Storage::Creator.track_uploadable_storage(subject, hosts: [])
    assert subject.valid?

    assert_difference("Storage::Purge.count", 1) do
      subject.cleanup!
    end
    assert_nil subject.storage_blob_id
  end

  test "doesn't fail if storage_blob_id is already nil" do
    blob = create :storage_blob
    subject = create(:upload_manifest_file,
      size: blob.size,
      storage_blob: blob,
    )
    GitHub::Storage::Creator.track_uploadable_storage(subject, hosts: [])
    assert subject.valid?
    subject.update_attribute(:storage_blob_id, nil)

    assert_difference("Storage::Purge.count", 1) do
      subject.cleanup!
    end
  end

  test "doesn't do anything if run twice" do
    blob = create :storage_blob
    subject = create(:upload_manifest_file,
      size: blob.size,
      storage_blob: blob,
    )
    GitHub::Storage::Creator.track_uploadable_storage(subject, hosts: [])
    assert subject.valid?
    subject.cleanup!

    assert_difference("Storage::Purge.count", 0) do
      subject.cleanup!
    end
  end

  test "clears storage_blob_id even if already purged" do
    blob = create :storage_blob
    subject = create(:upload_manifest_file,
      size: blob.size,
      storage_blob: blob,
    )
    GitHub::Storage::Creator.track_uploadable_storage(subject, hosts: [])
    assert subject.valid?

    GitHub::Storage::Destroyer.dereference(subject)
    subject.cleanup!

    assert_nil subject.storage_blob_id
  end
end
