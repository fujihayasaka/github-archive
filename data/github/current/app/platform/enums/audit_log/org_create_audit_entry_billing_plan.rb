# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgCreateAuditEntryBillingPlan < Platform::Enums::Base
        description "The billing plans available for organizations."

        value "FREE", "Free Plan", value: "free"
        value "BUSINESS", "Team Plan", value: "business"
        value "BUSINESS_PLUS", "Enterprise Cloud Plan", value: "business_plus"
        value "UNLIMITED", "Legacy Unlimited Plan", value: "unlimited"
        value "TIERED_PER_SEAT", "Tiered Per Seat Plan", value: "tiered_per_seat"
      end
    end
  end
end
