# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotEngagedOssLanguageJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @ruby = create(:language_name, name: "Ruby", linguist_id: 326)
  end

  setup do
    enable_feature_flag(:copilot_chatterbox)
  end

  test "doesn't call command with flag disabled" do
    Copilot::LanguageRepositoryLoader.expects(:call).never
    assert_logged("Body" => "Skipping Copilot::EngagedOssLanguageJob") do
      Copilot::EngagedOssLanguageJob.perform_now(language: @ruby.name)
    end
  end

  test "doesn't call command with fake language" do
    fake = "spaghetti"

    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Starting Copilot::EngagedOssLanguageJob for #{fake}").once
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Copilot::EngagedOssLanguageJob - Language not found for #{fake}").once
    enable_feature_flag(:copilot_engaged_oss_job)
    Copilot::LanguageRepositoryLoader.expects(:call).never

    assert_logged("Body" => "Performing Copilot::EngagedOssLanguageJob") do
      assert_logged("Body" => "Language not found") do
        Copilot::EngagedOssLanguageJob.perform_now(language: fake)
      end
    end
  end

  test "calls when the flag is enabled" do
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Starting Copilot::EngagedOssLanguageJob for Ruby").once
    GitHub::Chatterbox.client.expects(:say!).with(Copilot::DEFAULT_SLACK_CHANNEL, "Finished Copilot::EngagedOssLanguageJob for Ruby").once
    enable_feature_flag(:copilot_engaged_oss_job)
    Copilot::LanguageRepositoryLoader.expects(:call).once

    assert_logged("Body" => "Performing Copilot::EngagedOssLanguageJob") do
      Copilot::EngagedOssLanguageJob.perform_now(language: @ruby.name)
    end
  end

  test "calls when the flag is enabled for nil language" do
    enable_feature_flag(:copilot_engaged_oss_job)
    Copilot::LanguageRepositoryLoader.expects(:call).once

    assert_logged("Body" => "Performing Copilot::EngagedOssLanguageJob") do
      Copilot::EngagedOssLanguageJob.perform_now(language: nil)
    end
  end
end if GitHub.copilot_enabled?
