# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseEnabledSettingValue < Platform::Enums::Base

      # Intended to represent settings values for any enterprise settings where
      # the possible options are:
      # - Enabled
      # - No policy

      description "The possible values for an enabled/no policy enterprise setting."

      value "ENABLED", "The setting is enabled for organizations in the enterprise."
      value "NO_POLICY", "There is no policy set for organizations in the enterprise."
    end
  end
end
