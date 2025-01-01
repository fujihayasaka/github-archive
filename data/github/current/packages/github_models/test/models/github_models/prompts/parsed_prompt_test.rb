# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::Prompts::ParsedPromptTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "monalisa"
    @repo = create :repository, owner: @owner, from_example: :simple

    @commit_metadata = { committer: @repo.owner, message: "Adding a prompt" }
  end

  context "#from_repo - file does not exist" do
    test "returns nil if file does not exist" do
      prompt = GitHubModels::Prompts::ParsedPrompt.from_repo(@repo, ".github/workflows/does-not-exist.prompt.md")
      assert_nil prompt
    end

    test "returns nil for empty path" do
      prompt = GitHubModels::Prompts::ParsedPrompt.from_repo(@repo, "")
      assert_nil prompt
    end
  end

  context "#from_repo - file exists" do
    test "returns prompt object when a valid prompt file exists in default branch" do
      default_branch = @repo.heads.find_or_build(@repo.default_branch)
      default_branch.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add("prompt1.prompt.md", <<~MD
          ---
          name: prompt1
          ---
          user:
            Summarize this {{article}}
          MD
        )
      end

      prompt = GitHubModels::Prompts::ParsedPrompt.from_repo(@repo, "prompt1.prompt.md")
      refute_nil prompt
      prompt = T.must(prompt)
      assert_equal "prompt1", prompt.name
      assert_equal 1, prompt.messages.size

      message = T.must(prompt.messages.first)
      assert_equal "user", message.role
      assert_equal "Summarize this {{article}}", message.content
    end

    test "returns prompt object when a valid prompt file exists in branch" do
      branch = @repo.heads.find_or_build("branch")
      branch.append_commit(@commit_metadata, @repo.owner) do |files|
        files.add("src/app/my-prompt.prompt.md", <<~MD
          You are a helpful assistant
          MD
        )
      end

      prompt = GitHubModels::Prompts::ParsedPrompt.from_repo(@repo, "src/app/my-prompt.prompt.md", branch.qualified_name)
      refute_nil prompt
      prompt = T.must(prompt)
      assert_equal 1, prompt.messages.size
      message = T.must(prompt.messages.first)
      assert_equal "user", message.role
      assert_equal "You are a helpful assistant", message.content
    end
  end

  context "#parse_from_md - no frontmatter" do
    test "defaults to user prompt" do
      metadata, messages = GitHubModels::Prompts::ParsedPrompt.parse_from_md("Summarize this {{article}}")

      assert_nil metadata
      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "user", message.role
      assert_equal "Summarize this {{article}}", message.content
    end

    test "supports multiple prompts separated by roles" do
      metadata, messages = GitHubModels::Prompts::ParsedPrompt.parse_from_md(<<~MD)
        user:
        Summarize this {{article}}
        assistant:
          Sure! Here is a summary of the article.
        MD
      assert_nil metadata

      assert_equal 2, messages.size
      assert_equal "user", T.must(messages[0]).role
      assert_equal "Summarize this {{article}}", T.must(messages[0]).content

      assert_equal "assistant", T.must(messages[1]).role
      assert_equal "Sure! Here is a summary of the article.", T.must(messages[1]).content
    end
  end

  context "#parse_from_md - with frontmatter" do
    test "returns metadata and messages" do
      metadata, messages = GitHubModels::Prompts::ParsedPrompt.parse_from_md(<<~MD)
        ---
        name: my-prompt
        ---
        user:
        Summarize this {{article}}
        MD
      assert_equal({ "name" => "my-prompt" }, metadata)

      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "user", message.role
      assert_equal "Summarize this {{article}}", message.content
    end

    test "defaults to user role" do
      metadata, messages = GitHubModels::Prompts::ParsedPrompt.parse_from_md(<<~MD)
        ---
        name: my-prompt
        ---
        Summarize this {{article}}
        MD
      assert_equal({ "name" => "my-prompt" }, metadata)

      assert_equal 1, messages.size
      message = T.must(messages.first)
      assert_equal "user", message.role
      assert_equal "Summarize this {{article}}", message.content
    end

    test "supports multiple prompts" do
      metadata, messages = GitHubModels::Prompts::ParsedPrompt.parse_from_md(<<~MD)
        ---
        name: my-prompt
        ---
        system:
        You are a helpful assistant

        user:
        Summarize this {{article}}

        user:
        another user prompt
        MD
      assert_equal({ "name" => "my-prompt" }, metadata)

      assert_equal 3, messages.size
      assert_equal "system", T.must(messages[0]).role
      assert_equal "You are a helpful assistant", T.must(messages[0]).content

      assert_equal "user", T.must(messages[1]).role
      assert_equal "Summarize this {{article}}", T.must(messages[1]).content

      assert_equal "user", T.must(messages[2]).role
      assert_equal "another user prompt", T.must(messages[2]).content
    end
  end
end
