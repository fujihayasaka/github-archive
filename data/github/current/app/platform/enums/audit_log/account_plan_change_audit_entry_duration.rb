# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class AccountPlanChangeAuditEntryDuration < Platform::Enums::Base
        docs_category :enterprise_admin
        description "The plan duration of a billing subscription."
        visibility :under_development

        value "MONTH", "The Subscription is billed monthly.", value: "month"
        value "YEAR", "The Subscription is billed yearly.", value: "year"
      end
    end
  end
end
