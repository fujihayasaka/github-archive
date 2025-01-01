# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::PromptDetectorTest < GitHub::TestCase
  test "recognizes prompt files" do
    prompts = Dir[Rails.root.join("packages/github_models/test/fixtures/prompt_detector/prompts/*")]
    prompts.each do |prompt|
      assert GitHubModels::PromptDetector.text_probably_contains_prompt?(prompt + File.read(prompt))
    end
  end

  test "recognizes non-prompt files" do
    non_prompts = Dir[Rails.root.join("packages/github_models/test/fixtures/prompt_detector/non_prompts/*")]
    non_prompts.each do |non_prompt|
      refute GitHubModels::PromptDetector.text_probably_contains_prompt?(non_prompt + File.read(non_prompt))
    end
  end
end
