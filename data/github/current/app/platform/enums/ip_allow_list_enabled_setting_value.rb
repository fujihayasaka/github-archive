# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class IpAllowListEnabledSettingValue < Platform::Enums::Base
      description "The possible values for the IP allow list enabled setting."

      # Setting values indicating whether IP allow list is enabled.
      value "ENABLED", "The setting is enabled for the owner."
      value "DISABLED", "The setting is disabled for the owner."
    end
  end
end
