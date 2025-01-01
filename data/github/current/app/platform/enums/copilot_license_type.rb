# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotLicenseType < Platform::Enums::Base
      description "Indicates the type of access a user has to GitHub Copilot"
      mobile_only true

      value "NO_ACCESS", "No access found", value: "no_access"
      value "COPILOT_INDIVIDUAL", "Individual access", value: "copilot_individual"
      value "COPILOT_BUSINESS", "Business access", value: "copilot_business"
      value "COPILOT_ENTERPRISE", "Enterprise access", value: "copilot_enterprise"
    end
  end
end
