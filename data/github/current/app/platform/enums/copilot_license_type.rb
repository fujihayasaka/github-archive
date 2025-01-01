# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CopilotLicenseType < Platform::Enums::Base
      description "Indicates the type of access a user has to GitHub Copilot"

      required_capabilities [:access_copilot_limited_graphql_api]

      value "NO_ACCESS", "No access found", value: "no_access"
      value "COPILOT_FREE", "Limited free access", value: "copilot_free"
      value "COPILOT_INDIVIDUAL", "Individual access", value: "copilot_individual"
      value "COPILOT_INDIVIDUAL_PRO_PLUS", "Individual access plus", value: "copilot_individual_pro_plus"
      value "COPILOT_BUSINESS", "Business access", value: "copilot_business"
      value "COPILOT_ENTERPRISE", "Enterprise access", value: "copilot_enterprise"
    end
  end
end
