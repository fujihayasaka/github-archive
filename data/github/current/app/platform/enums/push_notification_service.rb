# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PushNotificationService < Platform::Enums::Base
      description "A push notification service."
      required_capabilities [:mobile_only_schema_mask]

      value "FCM", "Google Firebase Cloud Messaging", value: "fcm"
    end
  end
end
