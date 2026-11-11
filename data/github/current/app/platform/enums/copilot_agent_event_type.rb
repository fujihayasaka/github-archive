# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotAgentEventType < Platform::Enums::Base
      description "Types of events that can trigger the creation of a Copilot Agent session."
      required_capabilities [:copilot_agents]

      # Mobile values will be prepended with the platform name (e.g. "ios_" or "android_").
      value "MISSION_CONTROL", "Triggered by mission control on GitHub Mobile.", value: "mobile_mission_control", required_capabilities: [:mobile_only_schema_mask]
      value "REPO_PROFILE", "Triggered by repository profile on GitHub Mobile.", value: "mobile_repo_profile", required_capabilities: [:mobile_only_schema_mask]

      # Fallback values for other platforms or unknown events.
      value "UNKNOWN", "Triggered by an unknown event.", value: "unknown_graphql_event"
    end
  end
end
