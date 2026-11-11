# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationTermsOfServiceType < Platform::Enums::Base
      description "The type of terms of service for an organization."
      visibility :internal

      value "STANDARD", "Standard terms of service", value: "Standard"
      value "CORPORATE", "Corporate terms of service", value: "Corporate"
      value "EVALUATION", "Evaluation terms of service", value: "Evaluation"
      value "CUSTOM", "Custom terms of service", value: "Custom"
      value "ESA_EDUCATION", "Corporate ESA/Education terms of service", value: "ESA+Education"
    end
  end
end
