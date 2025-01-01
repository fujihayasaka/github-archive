# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PushNotificationService < Platform::Enums::Base
      description "A push notification service."
      mobile_only true

      value "FCM", "Google Firebase Cloud Messaging", value: "fcm"
    end
  end
end
