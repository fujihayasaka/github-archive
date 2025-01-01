# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::Prompts::FrontMatterTest < GitHub::TestCase
  context "#metadata" do
    test "returns metadata from basic markdown" do
      content = <<~MD
        ---
        name: prompt1
        ---
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      metadata = front_matter.metadata
      assert_equal "prompt1", T.must(metadata)["name"]
    end

    test "returns nested yaml" do
      content = <<~MD
        ---
        name: prompt1
        description: This is a prompt
        model: azure-openai/gpt-4o
        modelParameters:
          temperature: 0.5
        ---
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      metadata = front_matter.metadata
      assert_equal "prompt1", T.must(metadata)["name"]
      assert_equal "This is a prompt", T.must(metadata)["description"]
      assert_equal "azure-openai/gpt-4o", T.must(metadata)["model"]
      assert_equal 0.5, T.must(metadata)["modelParameters"]["temperature"]
      assert_nil T.must(metadata)["user"]
    end

    test "returns nil for invalid YAML" do
      content = <<~MD
        ---
        name: prompt1
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      metadata = front_matter.metadata
      assert_nil metadata
    end

    test "returns nil when no front matter is present" do
      content = <<~MD
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      metadata = front_matter.metadata
      assert_nil metadata
    end
  end

  context "#content" do
    test "returns content without front matter" do
      content = <<~MD
        ---
        name: prompt1
        ---
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      assert_equal "user:\n  Summarize this {{article}}\n", front_matter.content
    end

    test "returns empty string when content is nil" do
      front_matter = GitHubModels::Prompts::FrontMatter.new(nil)
      assert_equal "", front_matter.content
    end

    test "returns original content when no front matter is present" do
      content = <<~MD
        user:
          Summarize this {{article}}
        MD
      front_matter = GitHubModels::Prompts::FrontMatter.new(content)
      assert_equal content, front_matter.content
    end
  end
end
