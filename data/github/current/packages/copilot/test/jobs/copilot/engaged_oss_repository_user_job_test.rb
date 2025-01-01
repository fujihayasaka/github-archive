# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CopilotEngagedOssRepositoryUserJobTest < GitHub::TestCase
  include JobTestHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @repo = create(:repository)
  end

  test "doesn't call command with flag disabled" do
    Copilot::RepositoryUserLoader.expects(:call).never
    assert_logged("Body" => "Skipping Copilot::EngagedOssRepositoryUserJob") do
      Copilot::EngagedOssRepositoryUserJob.perform_now(@repo.id)
    end
  end

  test "doesn't call command with non-existent repo" do
    enable_feature_flag(:copilot_engaged_oss_job)
    Copilot::RepositoryUserLoader.expects(:call).never

    assert_logged("Body" => "Repository not found") do
      Copilot::EngagedOssRepositoryUserJob.perform_now(@repo.id + 1)
    end
  end


  test "calls when the flag is enabled" do
    enable_feature_flag(:copilot_engaged_oss_job)
    Copilot::RepositoryUserLoader.expects(:call).once

    assert_logged("Body" => "Performing Copilot::EngagedOssRepositoryUserJob") do
      Copilot::EngagedOssRepositoryUserJob.perform_now(@repo.id)
    end
  end
end
