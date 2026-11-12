module API
  module Enums
    class Severity < Types::BaseEnum
      description "A vulnerability severity"

      value "LOW", value: "low"
      value "MODERATE", value: "moderate"
      value "HIGH", value: "high"
      value "CRITICAL", value: "critical"
    end
  end
end
