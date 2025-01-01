# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotLimitedFeature < Platform::Enums::Base
      description "The type of the activity that was performed."

      required_capabilities [:access_copilot_limited_graphql_api]

      value "CHAT", "Copilot Chat.", value: "chat"
      value "COMPLETIONS", "Copilot IDE completions.", value: "completions"
    end
  end
end
