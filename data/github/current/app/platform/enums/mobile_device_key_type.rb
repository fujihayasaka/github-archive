# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MobileDeviceKeyType < Platform::Enums::Base
      description "The type of mobile device key that the device is registering"

      required_capabilities [:mobile_only_schema_mask]

      value "AUTH", "An auth mobile device key can be used for authentication mechanisms like two factor authentication", value: :auth
      value "RECOVERY", "A recovery mobile device key can be used for account recovery", value: :recovery
    end
  end
end
