# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryAdvisorySeverity < Platform::Enums::Base
      description "Severity of the vulnerability."
      visibility :internal

      value "LOW", "Low.", value: "low"
      value "MODERATE", "Moderate.", value: "moderate"
      value "HIGH", "High.", value: "high"
      value "CRITICAL", "Critical.", value: "critical"
    end
  end
end
