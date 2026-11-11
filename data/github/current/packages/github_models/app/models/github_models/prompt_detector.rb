# typed: true
# frozen_string_literal: true

class GitHubModels::PromptDetector
  # Fast heuristic classifier to avoid showing Models UI next to code that doesn't contain a prompt.
  # For the details on how these keywords and scores were arrived at and validated, see the ADR here:
  # https://github.com/github/models/pull/874
  def self.text_probably_contains_prompt?(text)
    keywords = {
      "prompt.md" => 6,
      "https://models.inference.ai.azure.com" => 5,
      "prompt =" => 3,
      "openai" => 4,
      "azure.ai.inference" => 5,
      "messages: [" => 4.579,
      "+ model:" => 1.558,
      "\"You are" => 3.458,
      "are an" => 2.452,
      "+ messages:" => -0.55,
      "+ \"title\":" => 1.442,
      "concise" => -1,
      "\"system\"," => 4.423,
      "the user's" => 3.415,
      "You are a" => 2.41,
      "{ role:" => 3.407,
      "role: \"user\"," => 1,
      "model:" => 2.394,
      "temperature:" => 1,
      "apiKey" => 2.2,
      "task is to" => -1.8,
      "are a helpful" => 0.374,
      "}, + ]," => 3.367,
      "##" => -2,
      "= false;" => -3,
      "= true;" => -6,
      "Binary files a/" => -5,
      ".css" => 1,
      "/>" => -4,
      "game" => -8,
    }
    threshold = 6

    score = 0
    keywords.each do |k, weight|
      score += weight if text.include?(k)
    end

    score > threshold
  end
end
