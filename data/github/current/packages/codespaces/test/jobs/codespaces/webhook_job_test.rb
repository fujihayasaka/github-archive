# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::WebhookJobTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    repo = create(:repository, owner: @owner, from_example: :emojis)
    @codespace = create(:codespace, :stopped_in_vscs, repository: repo)
    @git_status = {
      "commit" => "fceb75e8995eaa6eb5c996111dc2bf7d8679cd99",
      "branch" => "master",
      "hasUncommittedChanges" => true,
      "ahead" => 3,
      "behind" => 21
    }
    @valid_payload = {
      id: @codespace.guid,
      friendlyName: @codespace.name,
      state: Codespaces::Vscs::State::AVAILABLE,
      gitStatus: @git_status
    }
  end

  test "it delegates to Codespaces::ProcessWebhook" do
    Codespaces::ProcessWebhook.expects(:call).with(@valid_payload)
    Codespaces::WebhookJob.perform_now(@valid_payload)
  end

  test "uses a write connection and updates the codespace's environment data" do
    Codespaces::WebhookJob.perform_now(@valid_payload)
    @codespace.reload
    assert_equal Codespaces::Vscs::State::AVAILABLE, @codespace.environment_data.state
  end

  test "it retries on GitRPC::Error" do
    Codespaces::ProcessWebhook.expects(:call).at_least_once.raises(GitRPC::InvalidRepository)

    Codespaces::WebhookJob.any_instance.expects(:retry_job)

    assert_nothing_raised do
      Codespaces::WebhookJob.perform_now(@valid_payload)
    end
  end
end
