# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class AttachMatchingAssetsJobTest < GitHub::TestCase
  include JobTestHelper
  include UploadableTestHelpers

  fixtures do
    GitHub.user_images_cdn_url = "https://user-images-cdn.githubusercontent.com/"
    @owner = create(:user)
    @uploader = create(:user)
    @author = create(:verified_user)
    @repo = create :repository, owner: @author, has_discussions: true

    @issue = create(:issue, user: @author, repository: @repo)

    @asset = save_file_for_uploadable(UserAsset.new(uploader: @uploader))
  end

  teardown_once do
    GitHub.s3_uploads_enabled = nil
    GitHub.user_images_cdn_url = nil
  end

  environments = {
    s3: lambda {
      GitHub.s3_uploads_enabled = true
    },
  }

  environments.each do |upload_type, env_settings|
    test "#{upload_type} uploads: adds attachments on update" do
      env_settings.call

      perform_enqueued_jobs(only: [AttachMatchingAssetsJob, IssueOrchestration.job_class]) do
        @issue.update_body(attachment_body_for(@asset), @author)
      end

      assert_equal 1, @asset.attachments.count
      assert_equal 1, @issue.attachments.count
    end
  end

  def attachment_body_for(*assets)
    bodies = assets.map do |asset|
      "yo ![](#{asset.storage_external_url}) ![](foo.jpg)"
    end
    bodies.join("\n")
  end
end
