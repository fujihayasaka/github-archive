# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PlanFeatureLimit < Platform::Enums::Base
      mobile_only true

      description <<~MD
        Set of features limits which are supported based on the billing plan.
      MD

      GitHub::Plan::LIMITS.each do |name, desc|
        value name.to_s.upcase do
          value name
          description desc
        end
      end
    end
  end
end
