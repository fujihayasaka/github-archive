# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileCopilotPaywallIcon < Platform::Enums::Base
      description "Icons used in the Copilot paywall feature comparison table"

      required_capabilities [:mobile_only_schema_mask]

      value "NONE", "No icon displayed", value: "none"
      value "UNLIMITED", "Unlimited/infinity icon", value: "unlimited"
      value "RELOAD", "Reload/refresh icon", value: "reload"
      value "CHECK", "Check/checkmark icon", value: "check"
    end
  end
end
