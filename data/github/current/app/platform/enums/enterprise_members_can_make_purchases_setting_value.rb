# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseMembersCanMakePurchasesSettingValue < Platform::Enums::Base

      # Represents the following possible values for the members can make purchases setting
      # - enabled
      # - disabled

      description "The possible values for the members can make purchases setting."

      value "ENABLED", "The setting is enabled for organizations in the enterprise."
      value "DISABLED", "The setting is disabled for organizations in the enterprise."
    end
  end
end
