# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module CopilotPLG
  class UploadBannerUserIdsJobTest < GitHub::TestCase
    include JobTestHelper

    setup do
      @user_ids = %w(12345 67890 11223344)
      @copilot_survey_slug = "some-slug-name"
    end

    context "perform" do
      test "sets user IDs in KV store with correct slug" do
        perform_enqueued_jobs(only: [UploadBannerUserIdsJob]) do
          CopilotPLG::UploadBannerUserIdsJob.perform_now(user_ids: @user_ids, slug: @copilot_survey_slug)
        end
        # Check the kv values
        @user_ids.each do |user_id|
          assert_equal true.to_json, CopilotPLG::KV.get("user.some-slug-name-visible.#{user_id}").value { false.to_json }
        end
      end
    end
  end
end
