# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PlanFeature < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]

      description <<~MD
        Set of features which are supported based on the billing plan.
      MD

      GitHub::Plan::FEATURES.each do |name, desc|
        value name.to_s.upcase do
          if name == :private_secrets_and_variables
            visibility :internal
          end
          value name
          description desc
        end
      end
    end
  end
end
