# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileLiveActivityType < Platform::Enums::Base
      docs_category :meta
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different types of mobile live activities."

      value "COPILOT_CODING_AGENT", "Live activity for Copilot Coding Agent.", value: "live_activity_copilot_coding_agent"
      value "COPILOT_REMOTE_CONTROL", "Live activity for Copilot Remote Control.", value: "live_activity_copilot_remote_control"
    end
  end
end
