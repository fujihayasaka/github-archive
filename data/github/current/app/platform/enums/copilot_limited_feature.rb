# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotLimitedFeature < Platform::Enums::Base
      docs_category :copilot
      description "The type of the activity that was performed."

      required_capabilities [:access_copilot_limited_graphql_api]

      value "CHAT", "Copilot Chat.", value: "chat"
      value "COMPLETIONS", "Copilot IDE completions.", value: "completions"
      value "PREMIUM_INTERACTIONS", "Copilot premium interactions.", value: "premium_interactions"
      value "IMMEDIATE_USAGE_INTERVAL", "Copilot immediate usage interval.", value: "immediate_usage_interval"
      value "EXTENDED_USAGE_INTERVAL", "Copilot extended usage interval.", value: "extended_usage_interval"
    end
  end
end
