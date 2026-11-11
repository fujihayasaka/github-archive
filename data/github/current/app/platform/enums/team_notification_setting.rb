# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamNotificationSetting < Platform::Enums::Base
      description "The possible team notification values."

      value "NOTIFICATIONS_ENABLED", "Everyone will receive notifications when the team is @mentioned.", value: "notifications_enabled"
      value "NOTIFICATIONS_DISABLED", "No one will receive notifications.", value: "notifications_disabled"
    end
  end
end
