# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotCompletionJobStatusTest < GitHub::TestCase
  fixtures do
    @repo = create :repository
    @user = create :user
  end

  test "doesn't support #new" do
    refute Copilot::CompletionJobStatus.respond_to?(:new)
  end

  test "generates a distinct ID" do
    status = Copilot::CompletionJobStatus.create

    assert status.id.starts_with?("copilot-completion:"),
      "Expected generated ID to have distinct prefix"
  end

  test "sets an initial TTL of 3 days" do
    status = Copilot::CompletionJobStatus.create

    assert_equal status.ttl, 3.days
  end

  test "supports unstructured context" do
    status = Copilot::CompletionJobStatus.create(
      context: { repo_id: 42, completion: "Hello world!" }
    )

    json = status.as_json
    assert_equal 42, json[:context][:repo_id]
    assert_equal "Hello world!", json[:context][:completion]
  end

  test "sets expiration to 1 day on success" do
    status = Copilot::CompletionJobStatus.create

    status.expects(:expire).with(ttl: 1.day)
    status.success!

    assert_equal "success", status.state
  end

  test "sets expiration to 1 day on error" do
    status = Copilot::CompletionJobStatus.create

    status.expects(:expire).with(ttl: 1.day)
    status.error! "BOOM"

    assert_equal "error", status.state
    assert_equal "BOOM", status.error_message
  end

  context "#repository" do
    test "is pulled from the context" do
      status = Copilot::CompletionJobStatus.create(
        context: { repository_id: @repo.id }
      )

      assert_equal @repo, status.repository
    end

    test "can be supplied on create" do
      status = Copilot::CompletionJobStatus.create(
        repository: @repo
      )

      context = T.must(status.context)
      assert_equal @repo.id, context[:repository_id]
      assert_equal @repo, status.repository
    end

    test "can be set on the instance" do
      status = Copilot::CompletionJobStatus.create
      status.repository = @repo

      context = T.must(status.context)
      assert_equal @repo.id, context[:repository_id]
      assert_equal @repo, status.repository
    end
  end

  context "#actor" do
    test "is pulled from the context" do
      status = Copilot::CompletionJobStatus.create(
        context: { actor_id: @user.id }
      )

      assert_equal @user, status.actor
    end

    test "can be supplied on create" do
      status = Copilot::CompletionJobStatus.create(
        actor: @user
      )

      context = T.must(status.context)
      assert_equal @user.id, context[:actor_id]
      assert_equal @user, status.actor
    end

    test "can be set on the instance" do
      status = Copilot::CompletionJobStatus.create
      status.actor = @user

      context = T.must(status.context)
      assert_equal @user.id, context[:actor_id]
      assert_equal @user, status.actor
    end
  end
end
