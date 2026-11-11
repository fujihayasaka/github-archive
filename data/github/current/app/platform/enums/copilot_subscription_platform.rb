# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotSubscriptionPlatform < Platform::Enums::Base
      # This enum is used to provide client apps with information about Copilot in-app purchase eligibility.
      description "Indicates the platform that the user's Copilot subscription is managed on."

      required_capabilities [:mobile_only_schema_mask]

      value "APPLE", "Managed by Apple App Store", value: "apple"
      value "GOOGLE", "Managed by Google Play Store", value: "google"
      value "WEB", "Managed by GitHub.com", value: "web"
      value "MANAGED", "Managed by your business or enterprise administrator", value: "managed"
      value "UNKNOWN", "Managed by an unknown source", value: "unknown"
    end
  end
end
