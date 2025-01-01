# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NotificationRestrictionSettingValue < Platform::Enums::Base
      description "The possible values for the notification restriction setting."

      visibility :public, environments: [:enterprise, :dotcom]

      # Setting values indicating whether notifications are restricted to only
      # verified domains belonging to an owner.
      value "ENABLED", "The setting is enabled for the owner."
      value "DISABLED", "The setting is disabled for the owner."
    end
  end
end
