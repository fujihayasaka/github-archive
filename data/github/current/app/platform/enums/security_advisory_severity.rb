# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SecurityAdvisorySeverity < Platform::Enums::Base
      docs_category :security_advisories
      description "Severity of the vulnerability."
      visibility :public

      value "LOW", "Low.", value: "low"
      value "MODERATE", "Moderate.", value: "moderate"
      value "HIGH", "High.", value: "high"
      value "CRITICAL", "Critical.", value: "critical"
      value "UNKNOWN", "Unknown.", value: "unknown"
    end
  end
end
