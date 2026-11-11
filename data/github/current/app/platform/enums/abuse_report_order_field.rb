# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AbuseReportOrderField < Platform::Enums::Base

      description "Properties by which abuse report connections can be ordered."
      visibility :internal

      value "CREATED_AT", "Order abuse reports by when they were created.", value: "created_at"
    end
  end
end
