# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotEngagedOssJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "doesn't call subjob with flag disabled" do
    Copilot::EngagedOssLanguageJob.expects(:perform_later).never

    assert_logged("Body" => "Skipping Copilot::EngagedOssJob") do
      assert_performed_jobs 0 do
        Copilot::EngagedOssJob.perform_now
      end
    end
  end

  test "queues subjobs" do
    GitHub.flipper[:copilot_engaged_oss_job].enable
    GitHub.flipper[:copilot_chatterbox].enable
    GitHub::Chatterbox.client.expects(:say!).at_least_once
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Starting Copilot::EngagedOssJob").once
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Finished Copilot::EngagedOssJob").once

    assert_logged("Body" => "Performing Copilot::EngagedOssJob") do
      assert_performed_jobs Copilot::COPILOT_ENGAGED_OSS_LANGUAGES.length + 1, only: Copilot::EngagedOssLanguageJob do
        Copilot::EngagedOssJob.perform_now
      end
    end
  end
end if GitHub.copilot_enabled?
