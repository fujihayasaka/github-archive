# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class Setting < ApplicationRecord::Domain::Copilot
    self.table_name = "copilot_settings"

    sig { returns(String) }
    def self.rule_class_name
      "Copilot::Settings::SettingRule"
    end

    include SettingsCore::SettingBase

    sig { override.returns(String) }
    def provider_name
      CopilotSettingsDbProvider::NAME
    end
  end
end
