# typed: true
# frozen_string_literal: true

module Audit
  module CategoryTypes

    TYPES = {
      APPLICATION_MANAGEMENT: "Application Management",
      AUTHENTICATION: "Authentication",
      AUTHORIZATION: "Authorization",
      BILLING_MANAGEMENT: "Billing Management",
      DEVICE_MANAGEMENT: "Device Management",
      DIRECTORY_MANAGEMENT: "Directory Management",
      ENTITLEMENT_MANAGEMENT: "Entitlement Management",
      GROUP_MANAGEMENT: "Group Management",
      IDENTITY_PROTECTION: "Identity Protection",
      KEY_MANAGEMENT: "Key Management",
      PASSWORD_MANAGEMENT: "Password Management",
      POLICY_MANAGEMENT: "Policy Management",
      RESOURCE_MANAGEMENT: "Resource Management",
      ROLE_MANAGEMENT: "Role Management",
      USER_MANAGEMENT: "User Management",
      OTHER: "Other",
    }.freeze

  end
end
