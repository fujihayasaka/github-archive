# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotCodeReviewFeedbackType < Platform::Enums::Base
      description "Type of feedback for a Copilot Code Review comment."
      required_capabilities [:mobile_only_schema_mask]

      value "POSITIVE", "Content created by Copilot was high quality and/or helpful.", value: "POSITIVE"
      value "NEGATIVE", "Content created by Copilot was low quality and/or not helpful", value: "NEGATIVE"
    end
  end
end
