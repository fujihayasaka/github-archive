# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AbuseReportFilter < Platform::Enums::Base

      description "Filter on whether an abuse report is resolved."
      visibility :under_development

      value "RESOLVED", "Return abuse reports that are marked as resolved.", value: "resolved"
      value "UNRESOLVED", "Return abuse reports that are not marked as resolved.", value: "unresolved"
      value "ALL", "Return all abuse reports.", value: "all"
    end
  end
end
