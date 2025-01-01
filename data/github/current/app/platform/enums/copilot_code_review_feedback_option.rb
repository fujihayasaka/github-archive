# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotCodeReviewFeedbackOption < Platform::Enums::Base
      description "Feedback option for a Copilot Code Review comment."
      mobile_only true

      value "OFFENSIVE_OR_DISCRIMINATORY", "Comment is harmful or unsafe", value: "OFFENSIVE_OR_DISCRIMINATORY"
      value "POORLY_FORMATTED", "Comment is poorly formatted", value: "POORLY_FORMATTED"
      value "INCORRECT", "Comment is not true", value: "INCORRECT"
      value "UNHELPFUL", "Comment is not helpful", value: "UNHELPFUL"
      value "INCORRECT_LINE", "Comment is attached to the wrong line(s)", value: "INCORRECT_LINE"
      value "SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY", "Code suggestion is harmful or unsafe", value: "SUGGESTION_OFFENSIVE_OR_DISCRIMINATORY"
      value "SUGGESTION_POORLY_FORMATTED", "Code suggestion is poorly formatted", value: "SUGGESTION_POORLY_FORMATTED"
      value "SUGGESTION_UNHELPFUL", "Code suggestion does not solve the problem in the comment", value: "SUGGESTION_UNHELPFUL"
      value "SUGGESTION_INVALID", "Code suggestion is invalid", value: "SUGGESTION_INVALID"
    end
  end
end
