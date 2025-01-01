# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryFileTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @owner = create(:user, plan: :micro)
    @rando = create(:user)
    @repo = create(:repository, owner: @owner)
    @secret = create(:private_repository, owner: @owner)
    @asset = save_file_for_uploadable(
      RepositoryFile.new(uploader: @owner, repository: @repo),
      name: "test.pdf",
      content_type: "application/pdf",
    )
  end

  test "allows content types" do
    ctypes = RepositoryFile.allowed_content_types
    assert_includes ctypes, "application/pdf"
    assert_includes ctypes, "application/zip"
    assert_includes ctypes, "application/vnd.ms-excel"
    assert_includes ctypes, "text/csv"
    assert_includes ctypes, "text/markdown"
    assert_includes ctypes, "application/json"
  end

  test "requires repository, uploader, and manifest" do
    subject = RepositoryFile.create(
      repository: @repo,
      uploader: @owner,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    refute subject.new_record?
    assert subject.valid?
    assert_equal :s3_production_data, subject.storage_provider
  end

  test "prevents large file uploads" do
    subject = RepositoryFile.create(
      repository: @repo,
      uploader: @owner,
      name: "test.txt",
      content_type: "text/plain",
      size: 100.megabytes)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:size].empty?
    assert_equal subject.errors[:size][0], "File size too big: 25 MB are allowed, 100 MB were attempted to upload."
  end

  test "allow empty file uploads" do
    subject = RepositoryFile.create(
      repository: @repo,
      uploader: @owner,
      name: "test.txt",
      content_type: "text/plain",
      size: 0)

    refute subject.new_record?
    assert subject.valid?
  end

  test "uploader must have pull access to repository" do
    subject = RepositoryFile.create(
      repository: @secret,
      uploader: @rando,
      name: "test.txt",
      content_type: "text/plain",
      size: 42)

    assert subject.new_record?
    refute subject.valid?
    refute subject.errors[:uploader_id].empty?
  end

  test "sanitizes file name" do
    assert_name_sanitization RepositoryFile
  end

  test "requires matching file extension" do
    asset = RepositoryFile.new(uploader: @owner, repository: @repo)
    errored = false
    begin
      save_file_for_uploadable asset, name: "test.html", size: 1, content_type: "application/pdf"
    rescue ActiveRecord::RecordInvalid => err
      errored = true
      assert err.record.errors[:name]
    end
    assert errored
  end

  test "infers content type from file extension" do
    asset = RepositoryFile.new(uploader: @owner, repository: @repo)
    save_file_for_uploadable asset, name: "archive.ZIP", size: 1, content_type: ""
    assert_equal "application/zip", asset.content_type
  end

  test "fails to infer content type from extension" do
    asset = RepositoryFile.new(uploader: @owner, repository: @repo)
    errored = false
    begin
      save_file_for_uploadable asset, name: "test.xyz", size: 1, content_type: ""
    rescue ActiveRecord::RecordInvalid => err
      errored = true
      assert err.record.errors[:content_type]
    end
    assert errored
  end

  test "pulls content type from upload" do
    assert_equal "application/pdf", @asset.content_type
  end

  test "pulls size from upload" do
    assert_equal 1.kilobyte, @asset.size
  end

  test "pulls filename from upload" do
    assert_equal "test.pdf", @asset.name
  end

  test "builds s3 key" do
    if @asset.storage_provider == :s3_production_data
      assert_equal "#{@repo.id}/#{@asset.id}", @asset.storage_s3_key(@asset.storage_policy)
    else
      assert_equal "assets/repositories/#{@repo.id}/#{@asset.id}", @asset.storage_s3_key(@asset.storage_policy)
    end
  end

  test "sets s3 access" do
    assert_equal :private, @asset.storage_s3_access
  end

  test "storage enterprise policy" do
    GitHub.storage_cluster_enabled = true
    GitHub.s3_uploads_enabled = false
    assert_kind_of Storage::ClusterPolicy, @asset.storage_policy

    if GitHub.flipper[:new_repository_file_url].enabled?
      assert_match %r{user-attachments/files/#{@asset.id}/test.pdf}, @asset.url
    else
      assert_match %r{#{@repo.name_with_display_owner}/files/#{@asset.id}/test.pdf}, @asset.url
    end

    assert_match %r{/storage/repositories/#{@repo.id}/files/#{@asset.id}}, @asset.redirect_url
  end

  test "storage production policy with fastly acceleration" do
    GitHub.s3_uploads_enabled = true
    policy = @asset.storage_policy
    assert_kind_of Storage::S3Policy, policy
    assert_equal "private", policy.acl

    if GitHub.flipper[:new_repository_file_url].enabled?
      assert_match %r{/user-attachments/files/#{@asset.id}/test.pdf}, @asset.url
    else
      assert_match %r{/#{@repo.name_with_display_owner}/files/#{@asset.id}/test.pdf}, @asset.url
    end

    assert_match %r{\Ahttps://#{@asset.memory_alpha_fastly_acceleration_bucket(nil, nil)}/#{@asset.storage_s3_bucket}/#{@repo.id}/}, @asset.redirect_url
    assert_match /X-Amz-Expires=300/, @asset.redirect_url
    assert_match /response-content-disposition=attachment%3Bfilename%3Dtest\.pdf/, @asset.redirect_url
    assert_match /response-content-type=application%2Fpdf/, @asset.redirect_url
  end

  test "stores in alambic during create" do
    asset = RepositoryFile.new(uploader: @owner, repository: @repo)
    save_file_for_uploadable asset, name: "create.pdf", size: 2.kilobytes, content_type: "application/pdf"
  end

  test "stores in alambic during update" do
    asset = RepositoryFile.new(
      uploader: @owner,
      repository: @repo,
      name: "test.pdf",
      size: 1,
      content_type: "application/pdf")
    asset.save!

    assert_equal 1, asset.size
    assert_equal "application/pdf", asset.content_type

    asset = RepositoryFile.find(T.must(asset.id))
    save_file_for_uploadable asset, name: "update.pdf", size: 2.kilobytes, content_type: "application/pdf"

    assert asset.size > 1
    assert_equal "application/pdf", asset.content_type
  end

  test "preserves plus in filename" do
    filename = "this+has+plusses.pdf"
    asset = RepositoryFile.new uploader: @owner, repository: @repo
    save_file_for_uploadable asset, name: filename, content_type: "application/pdf"
    assert_match asset.name, filename
  end

  test "preserves at signs in filename" do
    filename = "this@has@at@signs.pdf"
    asset = RepositoryFile.new uploader: @owner, repository: @repo
    save_file_for_uploadable asset, name: filename, content_type: "application/pdf"
    assert_match asset.name, filename
  end

  test "downloads are instrumented" do
    events = subscribe "repository_files.download"
    @asset.download
    assert_equal 1, events.size
    assert event = events.first
    assert_equal @asset.size, event.payload[:size]
  end

  test "uses repo-less URL for new assets" do
    GitHub.flipper[:new_repository_file_url].enable

    asset = RepositoryFile.new(
      uploader: @owner,
      repository: @repo,
      name: "test.pdf",
      size: 1,
      content_type: "application/pdf")
    asset.save!

    assert asset.using_new_url?
    assert_match %r{/user-attachments/files/#{asset.id}/test.pdf}, asset.url

    GitHub.flipper[:new_repository_file_url].disable
  end

  test "uses legacy URL for legacy assets" do
    GitHub.flipper[:new_repository_file_url].enable

    asset = RepositoryFile.new(
      uploader: @owner,
      repository: @repo,
      name: "test.pdf",
      size: 1,
      content_type: "application/pdf")
    asset.stubs(:set_url_flag) # Stops `using_new_url` from being set
    asset.save!

    assert !asset.using_new_url?
    assert_match %r{/#{@repo.name_with_display_owner}/files/#{asset.id}/test.pdf}, asset.url

    GitHub.flipper[:new_repository_file_url].disable
  end

  context "open document formats" do
    test "text" do
      content_type = "application/vnd.oasis.opendocument.text"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".odt")
      assert_equal content_type, RepositoryFile.content_type_for_extension(".fodt")
    end

    test "spreadsheet" do
      content_type = "application/vnd.oasis.opendocument.spreadsheet"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".ods")
      assert_equal content_type, RepositoryFile.content_type_for_extension(".fods")
    end

    test "presentation" do
      content_type = "application/vnd.oasis.opendocument.presentation"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".odp")
      assert_equal content_type, RepositoryFile.content_type_for_extension(".fodp")
    end

    test "graphics" do
      content_type = "application/vnd.oasis.opendocument.graphics"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".odg")
      assert_equal content_type, RepositoryFile.content_type_for_extension(".fodg")
    end

    test "formula" do
      content_type = "application/vnd.oasis.opendocument.formula"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".odf")
    end

    test "zipped archive" do
      content_type = "application/gzip"

      ctypes = RepositoryFile.allowed_content_types
      assert_includes ctypes, content_type

      assert_equal content_type, RepositoryFile.content_type_for_extension(".gz")
      assert_equal content_type, RepositoryFile.content_type_for_extension(".tgz")
    end
  end
  context "has_access?" do
    test "repository files are accessible for public repositories" do
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
      )
      repository_file.save!
      assert repository_file.has_access?(@owner)
      assert repository_file.has_access?(@rando)
    end

    test "repository files are only accessible for authorized users for private repositories" do
      repo = create(:private_repository, owner: @owner)
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
      )
      repository_file.save!
      assert repository_file.has_access?(@owner)
      refute repository_file.has_access?(@rando)
    end

    test "not published repository advisories repository files are only accessible for authorized users" do
      GitHub.flipper[:secured_advisory_uploads].enable
      advisory = create(:repository_advisory, repository: @repo, author: @owner, state: "open")
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container: advisory
      )
      repository_file.save!
      assert repository_file.has_access?(@owner)
      refute repository_file.has_access?(@rando)

      advisory.add_collaborator(@rando)
      assert repository_file.has_access?(@rando)
    end

    test "not yet created repository repository advisories repository files are accessible for authorized users" do
      GitHub.flipper[:secured_advisory_uploads].enable
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container_type: RepositoryAdvisory.name
      )
      repository_file.save!
      assert repository_file.has_access?(@owner)
      refute repository_file.has_access?(@rando)
    end

    test "published repository advisories repository files are accessible for all users" do
      GitHub.flipper[:secured_advisory_uploads].enable
      advisory = create(:repository_advisory, repository: @repo, author: @owner, state: "published")
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container: advisory
      )
      repository_file.save!
      assert repository_file.has_access?(@rando)
    end

    test "not published repository advisories repository files are accessible for all users when feature flag is disabled for file uploader" do
      @owner.enable_feature(:secured_advisory_uploads)
      advisory = create(:repository_advisory, repository: @repo, author: @owner, state: "open")
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container: advisory
      )
      repository_file.save!

      refute repository_file.has_access?(@rando)

      @owner.disable_feature(:secured_advisory_uploads)

      assert repository_file.has_access?(@rando)
    end

    test "repository blob files are accessible for all users for public repositories" do
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container_type: UserAsset::REPOSITORY_BLOB
      )
      repository_file.save!

      assert repository_file.has_access?(@rando)
    end

    test "private repository blob files are accessible for authorized users" do
      repository_file = RepositoryFile.new(
        uploader: @owner,
        repository: @repo,
        name: "test.pdf",
        size: 1,
        content_type: "application/pdf",
        upload_container_type: UserAsset::REPOSITORY_BLOB
      )
      repository_file.save!

      assert repository_file.has_access?(@rando)
    end
  end
end
