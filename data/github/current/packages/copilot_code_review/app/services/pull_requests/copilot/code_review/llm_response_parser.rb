# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::LlmResponseParser
  sig { params(response: T.untyped).returns(String) }
  def self.extract_text(response)
    if response.key?("output")
      message_output = response["output"]&.find { |output| output["type"] == "message" }
      message_output&.dig("content", 0, "text") || ""
    else
      response.dig("choices", 0, "message", "content") || ""
    end
  end
end
