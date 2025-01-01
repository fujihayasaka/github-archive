# typed: true
# frozen_string_literal: true

module Newsies
  class SettingsStore < ::Newsies::ActiveRecordSettingsStore
    # Horcrux shim around NotificationUserSetting.  Content is returned as a
    # Newsies::Settings.
    #
    def initialize
      super NotificationUserSetting, SettingsSerializer,
        Newsies::Settings
    end
  end
end
