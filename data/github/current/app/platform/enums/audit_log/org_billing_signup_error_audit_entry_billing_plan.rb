# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgBillingSignupErrorAuditEntryBillingPlan < Platform::Enums::Base
        description "The billing plans available for Organizations."
        visibility :under_development

        value "BUSINESS", "Team Plan", value: "business"
        value "BUSINESS_PLUS", "Enterprise Cloud Plan", value: "business_plus"
      end
    end
  end
end
