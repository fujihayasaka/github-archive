# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileDeviceType < Platform::Enums::Base
      required_capabilities [:mobile_only_schema_mask]
      description "Represents the different mobile devices."

      value "PHONE", "Event came from a phone device.", value: "phone"
      value "TABLET", "Event came from a tablet device.", value: "tablet"
    end
  end
end
