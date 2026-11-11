# typed: strict
# frozen_string_literal: true

module Copilot::Settings
  class SettingRule < ApplicationRecord::Domain::Copilot
    self.table_name = "copilot_setting_rules"

    sig { returns(String) }
    def self.setting_class_name
      "Copilot::Settings::Setting"
    end

    sig { returns(String) }
    def self.condition_class_name
      "Copilot::Settings::ConditionExpression"
    end

    include SettingsCore::SettingRuleBase
  end
end
