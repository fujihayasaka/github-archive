# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseEnabledDisabledSettingValue < Platform::Enums::Base

      # Intended to represent settings values for any enterprise settings where
      # the possible options are:
      # - Enabled
      # - Disabled
      # - No policy

      description "The possible values for an enabled/disabled enterprise setting."

      value "ENABLED", "The setting is enabled for organizations in the enterprise."
      value "DISABLED", "The setting is disabled for organizations in the enterprise."
      value "NO_POLICY", "There is no policy set for organizations in the enterprise."
    end
  end
end
