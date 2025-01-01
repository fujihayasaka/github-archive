# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class BlockFromOrganizationDuration < Platform::Enums::Base
      description "An identifier value for a dashboard navigation link."
      required_capabilities [:mobile_only_schema_mask]

      ONE_DAY_VALUE     = 1
      THREE_DAYS_VALUE  = 3
      SEVEN_DAYS_VALUE  = 7
      THIRTY_DAYS_VALUE = 30
      INDEFINITE_VALUE  = -1

      value "ONE_DAY", "Block user for 1 day", value: ONE_DAY_VALUE
      value "THREE_DAYS", "Block user for 3 days", value: THREE_DAYS_VALUE
      value "SEVEN_DAYS", "Block user for 7 days", value: SEVEN_DAYS_VALUE
      value "THIRTY_DAYS", "Block user for 30 days", value: THIRTY_DAYS_VALUE
      value "INDEFINITE", "Block user indefinitely", value: INDEFINITE_VALUE
    end
  end
end
