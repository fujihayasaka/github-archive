# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::AttachmentTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    @uploaded_attachment = save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))
  end

  context "#storage_s3_access_key" do
    test "returns Azure storage account" do
      GitHub.stubs(:models_attachment_azure_storage_account).returns("foo")
      assert_equal "foo", @uploaded_attachment.storage_s3_access_key
    end
  end

  context "#storage_s3_secret_key" do
    test "returns Azure storage secret key" do
      GitHub.stubs(:models_attachment_azure_storage_secret_key).returns("bar")
      assert_equal "bar", @uploaded_attachment.storage_s3_secret_key
    end
  end

  context "#storage_s3_bucket" do
    test "returns Azure storage bucket name" do
      GitHub.stubs(:models_attachment_azure_storage_bucket).returns("baz")
      assert_equal "baz", @uploaded_attachment.storage_s3_bucket
    end
  end

  context "initialization" do
    test "pulls content type from upload" do
      assert_equal "image/jpeg", @uploaded_attachment.content_type
    end

    test "pulls size from upload" do
      assert_equal 1.kilobyte, @uploaded_attachment.size
    end

    test "pulls filename from upload" do
      assert_equal "pug.jpeg", @uploaded_attachment.name
    end

    test "sets raw asset uuid" do
      assert_equal @uploaded_attachment, GitHubModels::Attachment.find_by(guid: @uploaded_attachment.guid)
    end

    test "starts in the starter state" do
      assert_predicate GitHubModels::Attachment.new, :starter?
    end

    test "sets state on upload" do
      assert_predicate @uploaded_attachment, :uploaded?
    end
  end

  context ".allowed_content_types" do
    test "allows image content types" do
      content_types = GitHubModels::Attachment.allowed_content_types
      assert_includes content_types, "image/gif"
      assert_includes content_types, "image/png"
      assert_includes content_types, "image/jpeg"
      refute_includes content_types, "video/quicktime"
      refute_includes content_types, "video/mp4"
    end
  end

  context "validation" do
    test "requires an uploader" do
      models_attachment = GitHubModels::Attachment.new(uploader_id: nil)
      refute_predicate models_attachment, :valid?
      assert_includes models_attachment.errors[:uploader], "can't be blank"
    end

    test "requires a content type" do
      models_attachment = GitHubModels::Attachment.new(content_type: nil)
      refute_predicate models_attachment, :valid?
      assert_includes models_attachment.errors[:content_type], "is not included in the list"
    end

    test "requires size to be within limit" do
      too_big_size = (GitHubModels::Attachment::SIZE_LIMIT_IN_MEGABYTES + 1).megabytes
      models_attachment = GitHubModels::Attachment.new(size: too_big_size)
      refute_predicate models_attachment, :valid?
      error_message = models_attachment.errors[:size].first
      refute_nil error_message
      assert_includes error_message, "File is too big"
    end

    test "sanitizes file name" do
      assert_name_sanitization GitHubModels::Attachment
    end

    test "requires file extension to match content type" do
      models_attachment = GitHubModels::Attachment.new(uploader: @user)
      err = assert_raises(ActiveRecord::RecordInvalid) do
        save_file_for_uploadable models_attachment, name: "pug.html", content_type: "image/jpeg"
      end
      assert_includes err.record.errors[:name], "has a file extension that does not match the content type"
    end
  end

  context "uploaded_by scope" do
    test "filters by uploader" do
      other_user = create(:user)
      base_scope = GitHubModels::Attachment.where(id: [@uploaded_attachment.id])

      assert_equal [@uploaded_attachment], base_scope.uploaded_by(@user)
      assert_empty base_scope.uploaded_by(other_user)
    end
  end

  context "#target_for_conditional_access and #async_target_for_conditional_access" do
    test "returns the user who uploaded the attachment" do
      expected = @uploaded_attachment.uploader
      refute_nil expected

      assert_equal expected, @uploaded_attachment.target_for_conditional_access
      assert_equal expected, @uploaded_attachment.async_target_for_conditional_access.sync
    end
  end

  context "#permalink" do
    test "returns a url to GitHubModels::AttachmentsController#show" do
      assert_equal "/models/attachments/#{@uploaded_attachment.id}", @uploaded_attachment.permalink
    end

    test "#storage_external_url is equal to the permalink" do
      assert_equal @uploaded_attachment.permalink, @uploaded_attachment.storage_external_url
    end
  end
end if GitHub.models_enabled?
