# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class AttachMatchingGistAssetsJobTest < GitHub::TestCase
  include JobTestHelper
  include UploadableTestHelpers

  fixtures do
    GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
    @owner = create(:user)

    @asset = save_file_for_uploadable(UserAsset.new(uploader: @owner))
  end

  teardown_once do
    GitHub.s3_uploads_enabled = nil
    GitHub.user_images_cdn_url = nil
    GitHub.flipper[:gist_attachment_scanning].disable
  end

  environments = {
    s3: lambda {
      GitHub.s3_uploads_enabled = true
      GitHub.flipper[:gist_attachment_scanning].enable
    },
  }

  environments.each do |upload_type, env_settings|
    test "#{upload_type} uploads: adds attachments on update" do
      env_settings.call

      gist = perform_enqueued_jobs(only: [AttachMatchingGistAssetsJob]) do
        GistHelpers.generate(user: @owner, contents: [{ name: "file.txt", value: "hello world" }])
      end

      assert_equal 0, @asset.attachments.count
      assert_equal 0, gist.attachments.count

      contents = [
        { name: "file.md", value: attachment_body_for(@asset) },
      ]

      perform_enqueued_jobs(only: [AttachMatchingGistAssetsJob]) do
        gist.update!(contents: contents)
      end

      assert_equal 1, @asset.attachments.count
      assert_equal 1, gist.attachments.count
    end

    test "#{upload_type} uploads: adds attachments on create" do
      env_settings.call

      contents = [
        { name: "file1.md", value: attachment_body_for(@asset) },
      ]
      gist = perform_enqueued_jobs(only: [AttachMatchingGistAssetsJob]) do
        GistHelpers.generate(user: @owner, contents: contents)
      end

      assert_equal 1, @asset.attachments.count
      assert_equal 1, gist.attachments.count
    end
  end

  def attachment_body_for(*assets)
    bodies = assets.map do |asset|
      "yo ![](#{asset.storage_external_url}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end
end
