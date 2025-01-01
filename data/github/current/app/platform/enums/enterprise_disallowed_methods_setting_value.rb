# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseDisallowedMethodsSettingValue < Platform::Enums::Base

      # Intended to represent settings values for any enterprise settings where
      # the possible options are:
      # - Insecure
      # - No policy

      description "The possible values for an enabled/no policy enterprise setting."

      value "INSECURE", "The setting prevents insecure 2FA methods from being used by members of the enterprise."
      value "NO_POLICY", "There is no policy set for preventing insecure 2FA methods from being used by members of the enterprise."
    end
  end
end
