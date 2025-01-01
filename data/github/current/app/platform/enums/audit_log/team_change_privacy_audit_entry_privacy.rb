# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class TeamChangePrivacyAuditEntryPrivacy < Platform::Enums::Base
        description "The possible team privacy values."
        visibility :under_development

        value "VISIBLE", "The team is visible to every member of the organization.", value: "visible"
        value "SECRET", "The team is only visible to its members.", value: "secret"
      end
    end
  end
end
