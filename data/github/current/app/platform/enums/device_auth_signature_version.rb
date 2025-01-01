# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DeviceAuthSignatureVersion < Platform::Enums::Base
      description "Version of the signature being used for mobile device authentication requests."
      required_capabilities [:mobile_only_schema_mask]
      value "V1", "Indicates a base64 encoded signature of `signatureVersion|payload_bytes|challengeNum`", value: 1
    end
  end
end
