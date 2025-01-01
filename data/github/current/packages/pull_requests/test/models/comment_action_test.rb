# typed: true
# frozen_string_literal: true

require "test_helper"

class CommentActionTest < GitHub::TestCase
  test "stores and loads valid actions" do
    CommentAction.upsert!(
      repository:,
      comment_type:,
      comment_id:,
      actions: [
        {
          "name" => "Talk to the robot",
          "type" => "copilot-chat",
          "prompt" => "Hey there, Copilot!",
        },
        {
          "name" => "monalisa/smile",
          "type" => "link",
          "url" => "https://#{GitHub.host_name}/monalisa/smile",
        },
      ],
    )

    loaded = CommentAction.for(
      repository:,
      comment_type:,
      comment_id:,
    )

    assert_equal 2, loaded.count

    first_action = loaded.first
    fail "Expected a CopilotChatAction, got a #{first_action.class}" unless first_action.is_a?(CommentAction::Record::CopilotChatAction)
    assert_equal "Talk to the robot", first_action.name
    assert_equal "Hey there, Copilot!", first_action.prompt

    second_action = loaded.second
    fail "Expected a LinkAction, got a #{second_action.class}" unless second_action.is_a?(CommentAction::Record::LinkAction)
    assert_equal "monalisa/smile", second_action.name
    assert_equal "https://#{GitHub.host_name}/monalisa/smile", second_action.url
  end

  test "replaces existing actions with new ones" do
    CommentAction.upsert!(
      repository:,
      comment_type:,
      comment_id:,
      actions: [
        {
          "name" => "Talk to the robot",
          "type" => "copilot-chat",
          "prompt" => "Hey there, Copilot!",
        },
      ],
    )
    CommentAction.upsert!(
      repository:,
      comment_type:,
      comment_id:,
      actions: [
        {
          "name" => "monalisa/smile",
          "type" => "link",
          "url" => "https://#{GitHub.host_name}/monalisa/smile",
        },
      ],
    )

    loaded = CommentAction.for(
      repository:,
      comment_type:,
      comment_id:,
    )

    assert_equal 1, loaded.count

    action = loaded.first
    fail "Expected a LinkAction, got a #{action.class}" unless action.is_a?(CommentAction::Record::LinkAction)
    assert_equal "monalisa/smile", action.name
    assert_equal "https://#{GitHub.host_name}/monalisa/smile", action.url
  end

  test "deletes existing actions when given an empty list" do
    kv = PullRequests::KV.for_repository(repository)
    kv_key = "pull_requests/comment_actions/#{comment_type}#{comment_id}"

    CommentAction.upsert!(
      repository:,
      comment_type:,
      comment_id:,
      actions: [
        {
          "name" => "Talk to the robot",
          "type" => "copilot-chat",
          "prompt" => "Hey there, Copilot!",
        },
      ],
    )

    assert kv.exists(kv_key).value!

    CommentAction.upsert!(
      repository:,
      comment_type:,
      comment_id:,
      actions: [],
    )

    refute kv.exists(kv_key).value!

    loaded = CommentAction.for(
      repository:,
      comment_type:,
      comment_id:,
    )

    assert_predicate loaded, :empty?
  end

  test "rejects invalid action types" do
    assert_raises(ArgumentError, match: /\btype\b/i) do
      CommentAction.upsert!(
        repository:,
        comment_type:,
        comment_id:,
        actions: [
          {
            "name" => "Click me!",
            "type" => "execute-javascript",
            "script" => "doSomethingBad()",
          },
        ],
      )
    end
  end

  context ".safe_upsert" do
    test "logs errors instead of raising" do
      GitHub.logger.expects(:error).once.with(has_entries(
        "message": "Error writing comment actions",
        "exception": instance_of(ArgumentError),
        "gh.repo.id": repository.id,
        "gh.comment.type": comment_type,
        "gh.comment.id": comment_id,
        "code.function": "safe_upsert",
        "code.namespace": "CommentAction",
      ))

      result = CommentAction.safe_upsert(
        repository:,
        comment_type:,
        comment_id:,
        actions: [
          {
            "name" => "Click me!",
            "type" => "execute-javascript",
            "script" => "doSomethingBad()",
          },
        ],
      )

      refute result
    end
  end

  context "copilot-chat validations" do
    test "requires a name" do
      assert_raises(ArgumentError, match: /\bname\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => nil,
              "type" => "copilot-chat",
              "prompt" => "Hey there, Copilot!",
            },
          ],
        )
      end
    end

    test "requires a prompt" do
      assert_raises(ArgumentError, match: /\bprompt\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => "Talk to the robot",
              "type" => "copilot-chat",
              "prompt" => nil,
            },
          ],
        )
      end
    end
  end

  context "link validations" do
    test "requires a name" do
      assert_raises(ArgumentError, match: /\bname\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => nil,
              "type" => "link",
              "url" => "https://#{GitHub.host_name}/monalisa/smile",
            },
          ],
        )
      end
    end

    test "requires a url" do
      assert_raises(ArgumentError, match: /\burl\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => "monalisa/smile",
              "type" => "link",
              "url" => nil,
            },
          ],
        )
      end
    end

    test "requires a valid url" do
      assert_raises(ArgumentError, match: /\bwell-formed\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => "monalisa/smile",
              "type" => "link",
              "url" => "!!! Not a valid URL !!!",
            },
          ],
        )
      end
    end

    test "requires a HTTP url" do
      assert_raises(ArgumentError, match: /\bhttp\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => "Click me! I am definitely safe.",
              "type" => "link",
              "url" => "javascript:doBadThings()",
            },
          ],
        )
      end
    end

    test "requires a GitHub url" do
      assert_raises(ArgumentError, match: /\bGitHub\b/i) do
        CommentAction.upsert!(
          repository:,
          comment_type:,
          comment_id:,
          actions: [
            {
              "name" => "Click me! I am definitely safe.",
              "type" => "link",
              "url" => "http://phishing.example.com/",
            },
          ],
        )
      end
    end
  end

  private

  def repository = build_stubbed(:repository, id: 1)
  def comment_type = "TestComment"
  def comment_id = 1
end
