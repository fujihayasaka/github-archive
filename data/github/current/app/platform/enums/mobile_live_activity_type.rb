# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileLiveActivityType < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different types of mobile live activities."

      value "COPILOT_CODING_AGENT", "Live activity for Copilot Coding Agent.", value: "live_activity_copilot_coding_agent"
    end
  end
end
